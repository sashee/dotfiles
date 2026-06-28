use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};

use anyhow::Result;
use chrono::Local;
use host_tools_mcp::{
    create_server_dir, log_root, ProviderToServer, ServerToProvider, SOCKET_NAME,
};
use rmcp::model::{
    CallToolRequestParams, CallToolResult, CancelledNotificationParam, InitializeRequestParams,
    InitializeResult, ListToolsResult, PaginatedRequestParams, ProgressNotificationParam,
    ProgressToken, RequestId, ServerCapabilities, ServerInfo, Tool,
};
use rmcp::service::{NotificationContext, RequestContext};
use rmcp::{ErrorData, Peer, RoleServer, ServerHandler, ServiceExt};
use serde::Serialize;
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader, ReadBuf};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, oneshot};

#[derive(Clone)]
struct JsonLogger {
    file: Arc<Mutex<File>>,
}

impl JsonLogger {
    fn new(path: &Path) -> io::Result<Self> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        Ok(Self {
            file: Arc::new(Mutex::new(file)),
        })
    }

    fn log_value<T: Serialize>(&self, direction: &str, message: &T) -> io::Result<()> {
        let message = serde_json::to_value(message).map_err(io::Error::other)?;
        let line = serde_json::json!({
            "timestamp": Local::now().format("%Y-%m-%d %H:%M:%S%.3f %z").to_string(),
            "direction": direction,
            "message": message,
        });
        let mut file = self
            .file
            .lock()
            .map_err(|_| io::Error::new(io::ErrorKind::Other, "failed to lock log file"))?;
        serde_json::to_writer(&mut *file, &line).map_err(io::Error::other)?;
        file.write_all(b"\n")?;
        file.flush()
    }

    fn log_frame(&self, direction: &str, frame: &[u8]) -> io::Result<()> {
        let message = serde_json::from_slice::<Value>(frame).map_err(io::Error::other)?;
        self.log_value(direction, &message)
    }
}

struct LoggingReader<R> {
    inner: R,
    logger: JsonLogger,
    buffer: Vec<u8>,
}

impl<R> LoggingReader<R> {
    fn new(inner: R, logger: JsonLogger) -> Self {
        Self {
            inner,
            logger,
            buffer: Vec::new(),
        }
    }

    fn log_available_lines(&mut self) -> io::Result<()> {
        while let Some(index) = self.buffer.iter().position(|byte| *byte == b'\n') {
            let line = self.buffer.drain(..=index).collect::<Vec<_>>();
            let frame = trim_line_end(&line);
            if !frame.is_empty() {
                self.logger.log_frame("in", frame)?;
            }
        }
        Ok(())
    }
}

impl<R: AsyncRead + Unpin> AsyncRead for LoggingReader<R> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let filled_before = buf.filled().len();
        match Pin::new(&mut self.inner).poll_read(cx, buf) {
            Poll::Ready(Ok(())) => {
                let newly_read = &buf.filled()[filled_before..];
                if !newly_read.is_empty() {
                    self.buffer.extend_from_slice(newly_read);
                    self.log_available_lines()?;
                }
                Poll::Ready(Ok(()))
            }
            other => other,
        }
    }
}

struct LoggingWriter<W> {
    inner: W,
    logger: JsonLogger,
    buffer: Vec<u8>,
}

impl<W> LoggingWriter<W> {
    fn new(inner: W, logger: JsonLogger) -> Self {
        Self {
            inner,
            logger,
            buffer: Vec::new(),
        }
    }

    fn log_written_bytes(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.buffer.extend_from_slice(bytes);
        while let Some(index) = self.buffer.iter().position(|byte| *byte == b'\n') {
            let line = self.buffer.drain(..=index).collect::<Vec<_>>();
            let frame = trim_line_end(&line);
            if !frame.is_empty() {
                self.logger.log_frame("out", frame)?;
            }
        }
        Ok(())
    }
}

impl<W: AsyncWrite + Unpin> AsyncWrite for LoggingWriter<W> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize, io::Error>> {
        match Pin::new(&mut self.inner).poll_write(cx, buf) {
            Poll::Ready(Ok(count)) => {
                if count > 0 {
                    self.log_written_bytes(&buf[..count])?;
                }
                Poll::Ready(Ok(count))
            }
            other => other,
        }
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Result<(), io::Error>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

fn trim_line_end(line: &[u8]) -> &[u8] {
    if let Some(trimmed) = line.strip_suffix(b"\n") {
        if let Some(trimmed) = trimmed.strip_suffix(b"\r") {
            trimmed
        } else {
            trimmed
        }
    } else {
        line
    }
}

#[derive(Clone)]
struct HostToolsMcp {
    state: Arc<SharedState>,
}

struct SharedState {
    inner: Mutex<RegistryState>,
}

struct RegistryState {
    next_provider_id: u64,
    next_call_id: u64,
    peer: Option<Peer<RoleServer>>,
    providers: HashMap<u64, ProviderConnection>,
    tools: BTreeMap<String, RegisteredTool>,
    active_calls: HashMap<String, ActiveCall>,
}

struct ProviderConnection {
    sender: mpsc::UnboundedSender<ServerToProvider>,
    tools: BTreeSet<String>,
}

struct RegisteredTool {
    provider_id: u64,
    tool: Tool,
}

struct ActiveCall {
    provider_id: u64,
    tool_name: String,
    mcp_request_id: RequestId,
    peer: Peer<RoleServer>,
    progress_token: Option<ProgressToken>,
    result_tx: oneshot::Sender<Result<CallToolResult, ErrorData>>,
}

struct StartedCall {
    call_id: String,
    provider_id: u64,
    sender: mpsc::UnboundedSender<ServerToProvider>,
    receiver: oneshot::Receiver<Result<CallToolResult, ErrorData>>,
}

impl SharedState {
    fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryState {
                next_provider_id: 1,
                next_call_id: 1,
                peer: None,
                providers: HashMap::new(),
                tools: BTreeMap::new(),
                active_calls: HashMap::new(),
            }),
        }
    }

    fn set_peer(&self, peer: Peer<RoleServer>) {
        self.inner.lock().expect("registry lock poisoned").peer = Some(peer);
    }

    fn snapshot_tools(&self) -> Vec<Tool> {
        self.inner
            .lock()
            .expect("registry lock poisoned")
            .tools
            .values()
            .map(|registration| registration.tool.clone())
            .collect()
    }

    fn get_tool(&self, name: &str) -> Option<Tool> {
        self.inner
            .lock()
            .expect("registry lock poisoned")
            .tools
            .get(name)
            .map(|registration| registration.tool.clone())
    }

    fn allocate_provider_id(&self) -> u64 {
        let mut inner = self.inner.lock().expect("registry lock poisoned");
        let provider_id = inner.next_provider_id;
        inner.next_provider_id += 1;
        provider_id
    }

    fn insert_provider(&self, provider_id: u64, sender: mpsc::UnboundedSender<ServerToProvider>) {
        self.inner
            .lock()
            .expect("registry lock poisoned")
            .providers
            .insert(
                provider_id,
                ProviderConnection {
                    sender,
                    tools: BTreeSet::new(),
                },
            );
    }

    fn register_tools(
        &self,
        provider_id: u64,
        tools: Vec<Tool>,
    ) -> Result<Option<Peer<RoleServer>>, String> {
        let mut inner = self.inner.lock().expect("registry lock poisoned");
        if !inner.providers.contains_key(&provider_id) {
            return Err(format!("unknown provider {provider_id}"));
        }

        let mut names = BTreeSet::new();
        for tool in &tools {
            let name = tool.name.to_string();
            if !names.insert(name.clone()) {
                return Err(format!(
                    "tool {name} appears multiple times in one registration"
                ));
            }
            if inner.tools.contains_key(&name) {
                return Err(format!("tool {name} already exists"));
            }
        }

        for tool in tools {
            let name = tool.name.to_string();
            inner
                .tools
                .insert(name.clone(), RegisteredTool { provider_id, tool });
            inner
                .providers
                .get_mut(&provider_id)
                .expect("provider must exist")
                .tools
                .insert(name);
        }

        Ok(inner.peer.clone())
    }

    fn deregister_tools(
        &self,
        provider_id: u64,
        names: &[String],
    ) -> Result<Option<Peer<RoleServer>>, String> {
        let mut inner = self.inner.lock().expect("registry lock poisoned");
        let provider_tools = inner
            .providers
            .get(&provider_id)
            .ok_or_else(|| format!("unknown provider {provider_id}"))?
            .tools
            .clone();

        for name in names {
            if !provider_tools.contains(name) {
                return Err(format!(
                    "tool {name} is not registered by provider {provider_id}"
                ));
            }
        }

        let sender = inner
            .providers
            .get(&provider_id)
            .expect("provider must exist")
            .sender
            .clone();
        let removed_names = names.iter().cloned().collect::<BTreeSet<_>>();
        let call_ids = inner
            .active_calls
            .iter()
            .filter(|(_, call)| {
                call.provider_id == provider_id && removed_names.contains(&call.tool_name)
            })
            .map(|(call_id, _)| call_id.clone())
            .collect::<Vec<_>>();

        for name in names {
            inner.tools.remove(name);
        }
        if let Some(provider) = inner.providers.get_mut(&provider_id) {
            for name in names {
                provider.tools.remove(name);
            }
        }

        let peer = inner.peer.clone();
        let cancelled = call_ids
            .into_iter()
            .filter_map(|call_id| {
                inner.active_calls.remove(&call_id).map(|active_call| {
                    let _ = sender.send(ServerToProvider::CancelCall {
                        call_id: call_id.clone(),
                        reason: format!("tool {} was deregistered", active_call.tool_name),
                    });
                    let _ = active_call
                        .result_tx
                        .send(Err(cancellation_error("tool was deregistered")));
                })
            })
            .count();
        let _ = cancelled;
        Ok(peer)
    }

    fn disconnect_provider(&self, provider_id: u64) -> Option<Peer<RoleServer>> {
        let mut inner = self.inner.lock().expect("registry lock poisoned");
        let Some(provider) = inner.providers.remove(&provider_id) else {
            return inner.peer.clone();
        };

        for name in &provider.tools {
            inner.tools.remove(name);
        }

        let call_ids = inner
            .active_calls
            .iter()
            .filter(|(_, call)| call.provider_id == provider_id)
            .map(|(call_id, _)| call_id.clone())
            .collect::<Vec<_>>();
        for call_id in call_ids {
            if let Some(active_call) = inner.active_calls.remove(&call_id) {
                let _ = active_call
                    .result_tx
                    .send(Err(cancellation_error("tool provider disconnected")));
            }
        }

        inner.peer.clone()
    }

    fn start_call(
        &self,
        request: &CallToolRequestParams,
        context: &RequestContext<RoleServer>,
    ) -> Result<StartedCall, ErrorData> {
        let mut inner = self.inner.lock().expect("registry lock poisoned");
        let registration = inner
            .tools
            .get(request.name.as_ref())
            .ok_or_else(|| ErrorData::method_not_found::<rmcp::model::CallToolRequestMethod>())?;
        let provider_id = registration.provider_id;
        let sender = inner
            .providers
            .get(&provider_id)
            .ok_or_else(|| cancellation_error("tool provider disconnected"))?
            .sender
            .clone();
        let call_id = inner.next_call_id.to_string();
        inner.next_call_id += 1;
        let (result_tx, receiver) = oneshot::channel();
        inner.active_calls.insert(
            call_id.clone(),
            ActiveCall {
                provider_id,
                tool_name: request.name.to_string(),
                mcp_request_id: context.id.clone(),
                peer: context.peer.clone(),
                progress_token: context.meta.get_progress_token(),
                result_tx,
            },
        );

        Ok(StartedCall {
            call_id,
            provider_id,
            sender,
            receiver,
        })
    }

    fn complete_call(&self, call_id: &str, result: CallToolResult) {
        if let Some(active_call) = self
            .inner
            .lock()
            .expect("registry lock poisoned")
            .active_calls
            .remove(call_id)
        {
            let _ = active_call.result_tx.send(Ok(result));
        }
    }

    fn cancel_call_from_client(&self, call_id: &str, reason: &str) {
        let maybe_sender = {
            let mut inner = self.inner.lock().expect("registry lock poisoned");
            let Some(active_call) = inner.active_calls.remove(call_id) else {
                return;
            };
            inner
                .providers
                .get(&active_call.provider_id)
                .map(|provider| provider.sender.clone())
        };
        if let Some(sender) = maybe_sender {
            let _ = sender.send(ServerToProvider::CancelCall {
                call_id: call_id.to_string(),
                reason: reason.to_string(),
            });
        }
    }

    fn cancel_call_by_request_id(&self, request_id: &RequestId, reason: &str) {
        let maybe_call_id = {
            let inner = self.inner.lock().expect("registry lock poisoned");
            inner
                .active_calls
                .iter()
                .find(|(_, active_call)| &active_call.mcp_request_id == request_id)
                .map(|(call_id, _)| call_id.clone())
        };

        if let Some(call_id) = maybe_call_id {
            self.cancel_call_from_client(&call_id, reason);
        }
    }

    fn progress_target(&self, call_id: &str) -> Option<(Peer<RoleServer>, ProgressToken)> {
        let inner = self.inner.lock().expect("registry lock poisoned");
        let active_call = inner.active_calls.get(call_id)?;
        let token = active_call.progress_token.clone()?;
        Some((active_call.peer.clone(), token))
    }
}

impl ServerHandler for HostToolsMcp {
    fn initialize(
        &self,
        request: InitializeRequestParams,
        context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<InitializeResult, ErrorData>> + Send + '_ {
        if context.peer.peer_info().is_none() {
            context.peer.set_peer_info(request);
        }
        self.state.set_peer(context.peer.clone());
        std::future::ready(Ok(self.get_info()))
    }

    fn list_tools(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<ListToolsResult, ErrorData>> + Send + '_ {
        let tools = self.state.snapshot_tools();
        std::future::ready({
            let mut result = ListToolsResult::default();
            result.tools = tools;
            Ok(result)
        })
    }

    fn get_tool(&self, name: &str) -> Option<Tool> {
        self.state.get_tool(name)
    }

    fn call_tool(
        &self,
        request: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> impl std::future::Future<Output = Result<CallToolResult, ErrorData>> + Send + '_ {
        async move {
            let arguments = request.arguments.clone().unwrap_or_default();
            let started_call = self.state.start_call(&request, &context)?;
            let message = ServerToProvider::CallTool {
                call_id: started_call.call_id.clone(),
                tool: request.name.to_string(),
                arguments,
            };

            if started_call.sender.send(message).is_err() {
                self.state.disconnect_provider(started_call.provider_id);
                return Err(cancellation_error("tool provider disconnected"));
            }

            tokio::select! {
                result = started_call.receiver => match result {
                    Ok(result) => result,
                    Err(_) => Err(cancellation_error("tool provider disconnected")),
                },
                _ = context.ct.cancelled() => {
                    Err(cancellation_error("tool call cancelled"))
                }
            }
        }
    }

    fn on_cancelled(
        &self,
        notification: CancelledNotificationParam,
        _context: NotificationContext<RoleServer>,
    ) -> impl std::future::Future<Output = ()> + Send + '_ {
        self.state.cancel_call_by_request_id(
            &notification.request_id,
            notification
                .reason
                .as_deref()
                .unwrap_or("tool call cancelled"),
        );
        std::future::ready(())
    }

    fn get_info(&self) -> ServerInfo {
        ServerInfo::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_tool_list_changed()
        .build(),
        )
        .with_instructions(
            &format!(
                "Dynamic host tools are registered over the per-process UDS at {}/<datetime>/registry.sock",
                log_root().display()
            ),
        )
    }
}

async fn notify_tools_changed(peer: Option<Peer<RoleServer>>) {
    if let Some(peer) = peer {
        let _ = peer.notify_tool_list_changed().await;
    }
}

async fn handle_provider_message(
    state: Arc<SharedState>,
    provider_id: u64,
    message: ProviderToServer,
    sender: &mpsc::UnboundedSender<ServerToProvider>,
) {
    match message {
        ProviderToServer::RegisterTools { id, tools } => {
            match state.register_tools(provider_id, tools) {
                Ok(peer) => {
                    let _ = sender.send(ServerToProvider::Success { in_reply_to: id });
                    notify_tools_changed(peer).await;
                }
                Err(error) => {
                    let _ = sender.send(ServerToProvider::Error {
                        in_reply_to: id,
                        message: error,
                    });
                }
            }
        }
        ProviderToServer::DeregisterTools { id, tools } => {
            match state.deregister_tools(provider_id, &tools) {
                Ok(peer) => {
                    let _ = sender.send(ServerToProvider::Success { in_reply_to: id });
                    notify_tools_changed(peer).await;
                }
                Err(error) => {
                    let _ = sender.send(ServerToProvider::Error {
                        in_reply_to: id,
                        message: error,
                    });
                }
            }
        }
        ProviderToServer::ToolCallResult { call_id, result } => {
            state.complete_call(&call_id, result);
        }
        ProviderToServer::ToolCallProgress {
            call_id,
            progress,
            total,
            message,
        } => {
            if let Some((peer, token)) = state.progress_target(&call_id) {
                let notification = ProgressNotificationParam {
                    progress_token: token,
                    progress,
                    total,
                    message,
                };
                let _ = peer.notify_progress(notification).await;
            }
        }
    }
}

async fn provider_writer_task(
    mut receiver: mpsc::UnboundedReceiver<ServerToProvider>,
    mut writer: tokio::net::unix::OwnedWriteHalf,
    logger: JsonLogger,
) {
    while let Some(message) = receiver.recv().await {
        if logger.log_value("out", &message).is_err() {
            break;
        }
        let payload = match serde_json::to_vec(&message) {
            Ok(payload) => payload,
            Err(_) => break,
        };
        if writer.write_all(&payload).await.is_err() || writer.write_all(b"\n").await.is_err() {
            break;
        }
    }
}

async fn provider_reader_task(
    state: Arc<SharedState>,
    provider_id: u64,
    reader: tokio::net::unix::OwnedReadHalf,
    logger: JsonLogger,
    sender: mpsc::UnboundedSender<ServerToProvider>,
) {
    let mut reader = BufReader::new(reader);
    loop {
        let mut line = String::new();
        match reader.read_line(&mut line).await {
            Ok(0) => break,
            Ok(_) => {
                let raw = line.trim_end();
                let Ok(value) = serde_json::from_str::<Value>(raw) else {
                    let peer = state.disconnect_provider(provider_id);
                    notify_tools_changed(peer).await;
                    return;
                };
                if logger.log_value("in", &value).is_err() {
                    break;
                }
                let Ok(message) = serde_json::from_value::<ProviderToServer>(value) else {
                    let peer = state.disconnect_provider(provider_id);
                    notify_tools_changed(peer).await;
                    return;
                };
                handle_provider_message(state.clone(), provider_id, message, &sender).await;
            }
            Err(_) => break,
        }
    }

    let peer = state.disconnect_provider(provider_id);
    notify_tools_changed(peer).await;
}

async fn provider_connection_task(
    state: Arc<SharedState>,
    provider_id: u64,
    stream: UnixStream,
    log_dir: PathBuf,
) {
    let logger = match JsonLogger::new(&log_dir.join(format!("tool-provider-{provider_id}.log"))) {
        Ok(logger) => logger,
        Err(_) => return,
    };
    let (reader, writer) = stream.into_split();
    let (sender, receiver) = mpsc::unbounded_channel();
    state.insert_provider(provider_id, sender.clone());

    let writer_handle = tokio::spawn(provider_writer_task(receiver, writer, logger.clone()));
    provider_reader_task(state, provider_id, reader, logger, sender).await;
    writer_handle.abort();
}

async fn run_accept_loop(
    state: Arc<SharedState>,
    listener: UnixListener,
    log_dir: PathBuf,
) -> io::Result<()> {
    loop {
        let (stream, _) = listener.accept().await?;
        let provider_id = state.allocate_provider_id();
        tokio::spawn(provider_connection_task(
            state.clone(),
            provider_id,
            stream,
            log_dir.clone(),
        ));
    }
}

fn cancellation_error(reason: &str) -> ErrorData {
    ErrorData::internal_error(reason.to_string(), None)
}

#[tokio::main]
async fn main() -> Result<()> {
    let log_dir = create_server_dir()?;

    let stdio_logger = JsonLogger::new(&log_dir.join("server.log"))?;
    let stdin = LoggingReader::new(tokio::io::stdin(), stdio_logger.clone());
    let stdout = LoggingWriter::new(tokio::io::stdout(), stdio_logger);

    let state = Arc::new(SharedState::new());

    // Bind synchronously here (rather than inside the spawned task) so a failure
    // propagates to the process exit and is printed to stderr. A common, easily
    // missed failure: the socket path exceeds sun_path's 108-byte limit when
    // TMPDIR is deep (e.g. inside a Nix build sandbox), so include the length.
    let socket_path = log_dir.join(SOCKET_NAME);
    let _ = fs::remove_file(&socket_path);
    let listener = UnixListener::bind(&socket_path).map_err(|error| {
        anyhow::anyhow!(
            "failed to bind registry socket {} ({} bytes; sun_path limit is 108): {error}",
            socket_path.display(),
            socket_path.as_os_str().len()
        )
    })?;
    let listener_handle = tokio::spawn(run_accept_loop(state.clone(), listener, log_dir.clone()));

    let server = HostToolsMcp { state }.serve((stdin, stdout)).await?;
    let wait_result = server.waiting().await;
    listener_handle.abort();
    wait_result?;
    Ok(())
}
