use std::collections::HashMap;
use std::os::unix::process::ExitStatusExt;
use std::process::Stdio;

use anyhow::{anyhow, bail, Context, Result};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use rmcp::model::{CallToolResult, Content};
use serde::Deserialize;
use serde_json::{Map, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use tokio::process::Command;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::JoinSet;
use tokio::time::{timeout, Duration};

use crate::{
    debug_log, discover_live_servers, log_root, progress_message, LiveServer, ProgressUpdate,
    ProviderToServer, RegisteredCommand, ServerToProvider,
};

pub async fn run_register(mode: RegisteredCommand) -> Result<()> {
    debug_log(format!(
        "starting registration for tool {}",
        mode.tool_name()
    ));
    let servers = discover_live_servers().context("failed to discover host-tools-mcp servers")?;
    if servers.is_empty() {
        bail!(
            "no live host-tools-mcp servers found in {}",
            log_root().display()
        );
    }

    for server in &servers {
        debug_log(format!("will connect to {}", server.socket_path.display()));
    }

    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let mut connections = JoinSet::new();
    for server in servers {
        connections.spawn(connection_task(server, mode.clone(), shutdown_rx.clone()));
    }

    tokio::select! {
        result = async {
            let mut saw_connection = false;
            while let Some(joined) = connections.join_next().await {
                saw_connection = true;
                joined??;
            }
            if !saw_connection {
                bail!("no host-tools-mcp connections were started");
            }
            Ok::<(), anyhow::Error>(())
        } => result,
        signal = tokio::signal::ctrl_c() => {
            signal.context("failed to wait for ctrl-c")?;
            let _ = shutdown_tx.send(true);
            while let Some(joined) = connections.join_next().await {
                let _ = joined;
            }
            Ok(())
        }
    }
}

async fn connection_task(
    server: LiveServer,
    mode: RegisteredCommand,
    mut shutdown_rx: watch::Receiver<bool>,
) -> Result<()> {
    debug_log(format!(
        "connecting to {} for tool {}",
        server.socket_path.display(),
        mode.tool_name()
    ));
    let stream = UnixStream::connect(&server.socket_path)
        .await
        .with_context(|| format!("failed to connect to {}", server.socket_path.display()))?;
    debug_log(format!("connected to {}", server.socket_path.display()));
    let (reader, writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<ProviderToServer>();

    let writer_task = tokio::spawn(async move {
        let mut writer = writer;
        while let Some(message) = outbound_rx.recv().await {
            let payload = serde_json::to_vec(&message)
                .context("failed to encode outbound provider message")?;
            writer
                .write_all(&payload)
                .await
                .context("failed to write provider message")?;
            writer
                .write_all(b"\n")
                .await
                .context("failed to write provider newline")?;
        }
        Ok::<(), anyhow::Error>(())
    });

    outbound_tx
        .send(ProviderToServer::RegisterTools {
            id: 1,
            tools: vec![mode.tool_definition()],
        })
        .map_err(|_| anyhow!("failed to queue register_tools message"))?;
    debug_log(format!(
        "queued register_tools for {} on {}",
        mode.tool_name(),
        server.socket_path.display()
    ));

    let (events_tx, mut events_rx) = mpsc::unbounded_channel::<RunnerEvent>();
    let mut active_calls = HashMap::<String, ActiveCall>::new();
    let mut registration_complete = false;

    loop {
        tokio::select! {
            changed = shutdown_rx.changed() => {
                if changed.is_ok() && *shutdown_rx.borrow() {
                    cancel_active_calls(&mut active_calls);
                    break;
                }
            }
            maybe_event = events_rx.recv() => {
                let Some(event) = maybe_event else { continue; };
                match event {
                    RunnerEvent::Progress { call_id, update } => {
                        let _ = outbound_tx.send(ProviderToServer::ToolCallProgress {
                            call_id,
                            progress: update.progress,
                            total: update.total,
                            message: update.message,
                        });
                    }
                    RunnerEvent::Finished { call_id, result } => {
                        active_calls.remove(&call_id);
                        let _ = outbound_tx.send(ProviderToServer::ToolCallResult { call_id, result });
                    }
                }
            }
            line = read_line(&mut reader) => {
                let Some(line) = line? else {
                    debug_log(format!("server {} closed the connection", server.socket_path.display()));
                    cancel_active_calls(&mut active_calls);
                    break;
                };
                let message = serde_json::from_str::<ServerToProvider>(&line)
                    .context("failed to decode server message")?;
                match message {
                    ServerToProvider::Success { in_reply_to } if in_reply_to == 1 => {
                        registration_complete = true;
                        debug_log(format!(
                            "registration completed for {} on {}",
                            mode.tool_name(),
                            server.socket_path.display()
                        ));
                    }
                    ServerToProvider::Success { .. } => {}
                    ServerToProvider::Error { message, .. } => bail!(message),
                    ServerToProvider::CallTool { call_id, arguments, .. } => {
                        let (cancel_tx, cancel_rx) = oneshot::channel();
                        active_calls.insert(call_id.clone(), ActiveCall { cancel_tx });
                        tokio::spawn(run_command_call(
                            mode.clone(),
                            call_id,
                            arguments,
                            cancel_rx,
                            events_tx.clone(),
                        ));
                    }
                    ServerToProvider::CancelCall { call_id, .. } => {
                        if let Some(active_call) = active_calls.remove(&call_id) {
                            let _ = active_call.cancel_tx.send(());
                        }
                    }
                }
            }
        }
    }

    drop(outbound_tx);
    let _ = writer_task.await;

    if !registration_complete {
        bail!(
            "registration did not complete for {}",
            server.socket_path.display()
        );
    }

    debug_log(format!(
        "connection task finished cleanly for {}",
        server.socket_path.display()
    ));
    Ok(())
}

struct ActiveCall {
    cancel_tx: oneshot::Sender<()>,
}

enum RunnerEvent {
    Progress {
        call_id: String,
        update: ProgressUpdate,
    },
    Finished {
        call_id: String,
        result: CallToolResult,
    },
}

async fn run_command_call(
    mode: RegisteredCommand,
    call_id: String,
    arguments: Map<String, Value>,
    mut cancel_rx: oneshot::Receiver<()>,
    events_tx: mpsc::UnboundedSender<RunnerEvent>,
) {
    let result =
        run_command_call_inner(&mode, &arguments, &call_id, &mut cancel_rx, &events_tx).await;
    if let Ok(Some(result)) = result {
        let _ = events_tx.send(RunnerEvent::Finished { call_id, result });
    }
}

async fn run_command_call_inner(
    mode: &RegisteredCommand,
    arguments: &Map<String, Value>,
    call_id: &str,
    cancel_rx: &mut oneshot::Receiver<()>,
    events_tx: &mpsc::UnboundedSender<RunnerEvent>,
) -> Result<Option<CallToolResult>> {
    let (program, args) = match parse_command(mode, arguments) {
        Ok(command) => command,
        Err(result) => return Ok(Some(result)),
    };

    eprintln!("exec: {}", format_command_for_log(&program, &args));

    let mut command = Command::new(&program);
    command
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command
        .spawn()
        .with_context(|| format!("failed to spawn {program}"))?;

    let stdout = child.stdout.take().context("missing child stdout")?;
    let stderr = child.stderr.take().context("missing child stderr")?;
    let (output_tx, mut output_rx) = mpsc::unbounded_channel::<OutputEvent>();

    let stdout_handle = tokio::spawn(read_output_stream(
        stdout,
        OutputKind::Stdout,
        output_tx.clone(),
    ));
    let stderr_handle = tokio::spawn(read_output_stream(stderr, OutputKind::Stderr, output_tx));

    let mut stdout_lines = Vec::new();
    let mut stderr_lines = Vec::new();
    let mut next_progress = 1usize;
    let mut exit_status = None;

    loop {
        tokio::select! {
            status = child.wait(), if exit_status.is_none() => {
                exit_status = Some(status.context("failed to wait for child")?);
            }
            maybe_output = output_rx.recv() => {
                match maybe_output {
                    Some(OutputEvent::Line { kind, line }) => {
                        match kind {
                            OutputKind::Stdout => {
                                println!("{line}");
                                stdout_lines.push(line.clone());
                                let _ = events_tx.send(RunnerEvent::Progress {
                                    call_id: call_id.to_string(),
                                    update: progress_message(next_progress, "stdout", &line),
                                });
                            }
                            OutputKind::Stderr => {
                                eprintln!("{line}");
                                stderr_lines.push(line.clone());
                                let _ = events_tx.send(RunnerEvent::Progress {
                                    call_id: call_id.to_string(),
                                    update: progress_message(next_progress, "stderr", &line),
                                });
                            }
                        }
                        next_progress += 1;
                    }
                    Some(OutputEvent::Closed) => {}
                    None => {
                        if exit_status.is_some() {
                            break;
                        }
                    }
                }
            }
            _ = &mut *cancel_rx => {
                terminate_child(&mut child).await;
                let _ = stdout_handle.await;
                let _ = stderr_handle.await;
                eprintln!("exit: cancelled");
                return Ok(None);
            }
        }
    }

    let _ = stdout_handle.await;
    let _ = stderr_handle.await;
    let status = exit_status.context("child exited without status")?;

    if let Some(code) = status.code() {
        eprintln!("exit: code={code}");
    } else if let Some(signal) = status.signal() {
        eprintln!("exit: signal={signal}");
    } else {
        eprintln!("exit: unknown");
    }

    Ok(Some(build_result(status, stdout_lines, stderr_lines)))
}

fn parse_command(
    mode: &RegisteredCommand,
    arguments: &Map<String, Value>,
) -> std::result::Result<(String, Vec<String>), CallToolResult> {
    match mode {
        RegisteredCommand::Exact(argv) => {
            if !arguments.is_empty() {
                return Err(CallToolResult::error(vec![Content::text(
                    "This tool takes no arguments.".to_string(),
                )]));
            }
            Ok((argv[0].clone(), argv[1..].to_vec()))
        }
        RegisteredCommand::Exec(executable) => {
            #[derive(Deserialize)]
            #[serde(deny_unknown_fields)]
            struct ExecArgs {
                #[serde(default)]
                args: Vec<String>,
            }

            let parsed = serde_json::from_value::<ExecArgs>(Value::Object(arguments.clone()))
                .map_err(|error| {
                    CallToolResult::error(vec![Content::text(format!(
                        "Invalid args for executable tool: {error}"
                    ))])
                })?;
            Ok((executable.clone(), parsed.args))
        }
    }
}

fn build_result(
    status: std::process::ExitStatus,
    stdout_lines: Vec<String>,
    stderr_lines: Vec<String>,
) -> CallToolResult {
    let stdout = stdout_lines.join("\n");
    let stderr = stderr_lines.join("\n");

    let mut structured = Map::new();
    structured.insert(
        "exitCode".to_string(),
        status.code().map_or(Value::Null, |code| Value::from(code)),
    );
    if let Some(signal) = status.signal() {
        structured.insert("signal".to_string(), Value::from(signal));
    }
    structured.insert("stdout".to_string(), Value::from(stdout.clone()));
    structured.insert("stderr".to_string(), Value::from(stderr.clone()));

    let mut text_parts = Vec::new();
    if !stdout.is_empty() {
        text_parts.push(stdout);
    }
    if !stderr.is_empty() {
        text_parts.push(format_stderr_text(&stderr));
    }

    let content = if text_parts.is_empty() {
        Vec::new()
    } else {
        vec![Content::text(text_parts.join("\n"))]
    };

    let mut result = if status.success() {
        CallToolResult::structured(Value::Object(structured))
    } else {
        CallToolResult::structured_error(Value::Object(structured))
    };
    result.content = content;
    result
}

fn format_stderr_text(stderr: &str) -> String {
    stderr
        .lines()
        .map(|line| format!("stderr: {line}"))
        .collect::<Vec<_>>()
        .join("\n")
}

fn format_command_for_log(program: &str, args: &[String]) -> String {
    std::iter::once(program)
        .chain(args.iter().map(String::as_str))
        .map(shell_escape)
        .collect::<Vec<_>>()
        .join(" ")
}

fn shell_escape(value: &str) -> String {
    if !value.is_empty()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"@%_-+=:,./".contains(&byte))
    {
        value.to_string()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

#[derive(Debug)]
enum OutputEvent {
    Line { kind: OutputKind, line: String },
    Closed,
}

#[derive(Debug, Clone, Copy)]
enum OutputKind {
    Stdout,
    Stderr,
}

async fn read_output_stream<T: tokio::io::AsyncRead + Unpin>(
    stream: T,
    kind: OutputKind,
    output_tx: mpsc::UnboundedSender<OutputEvent>,
) {
    let mut reader = BufReader::new(stream);
    loop {
        let mut line = String::new();
        match reader.read_line(&mut line).await {
            Ok(0) => {
                let _ = output_tx.send(OutputEvent::Closed);
                break;
            }
            Ok(_) => {
                let _ = output_tx.send(OutputEvent::Line {
                    kind,
                    line: line.trim_end().to_string(),
                });
            }
            Err(_) => {
                let _ = output_tx.send(OutputEvent::Closed);
                break;
            }
        }
    }
}

async fn read_line<R: tokio::io::AsyncBufRead + Unpin>(reader: &mut R) -> Result<Option<String>> {
    let mut line = String::new();
    let read = reader
        .read_line(&mut line)
        .await
        .context("failed to read line")?;
    if read == 0 {
        Ok(None)
    } else {
        Ok(Some(line.trim_end().to_string()))
    }
}

fn cancel_active_calls(active_calls: &mut HashMap<String, ActiveCall>) {
    for (_, active_call) in active_calls.drain() {
        let _ = active_call.cancel_tx.send(());
    }
}

async fn terminate_child(child: &mut tokio::process::Child) {
    if let Some(pid) = child.id() {
        let _ = kill(Pid::from_raw(pid as i32), Signal::SIGTERM);
        if timeout(Duration::from_millis(1500), child.wait())
            .await
            .is_ok()
        {
            return;
        }
    }

    let _ = child.kill().await;
    let _ = child.wait().await;
}
