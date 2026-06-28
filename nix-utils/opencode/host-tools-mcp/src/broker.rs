//! Multiplexing broker for `host-tools-mcp`.
//!
//! The broker is a host-side process that speaks the registry protocol on BOTH
//! sides so a single forwarded socket can bridge a remote `mcp-register` to the
//! variable set of real registry servers (Claude, OpenCode, ...) on the laptop:
//!
//!   remote `mcp-register`  --(one ssh-forwarded socket)-->  broker.sock (front)
//!   broker  --(one provider connection each)-->  /tmp/host-tools-mcp/<ts>/registry.sock (back)
//!
//! - Front: the broker is the SERVER. A downstream provider (the remote
//!   `mcp-register`) connects, registers its tools once, and serves tool calls.
//! - Back: the broker is a PROVIDER toward every live registry, forwarding the
//!   downstream's tools and relaying calls. A reconciler keeps the upstream set
//!   in sync, so clients launched after the remote connects still get the tool.
//!
//! Each upstream registry has its own `call_id` space, so the broker rewrites
//! ids ([`CallRouter`]) to route a result back to the registry that issued the
//! call. All routing state for a downstream lives in its own task (no shared
//! mutable state); upstream relays are dumb pipes that tag messages with an
//! upstream id.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use rmcp::model::Tool;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::mpsc;

use crate::{
    debug_log, discover_live_servers, ProviderToServer, ServerToProvider, LiveServer,
};
// `broker_socket_path` lives in the crate root (shared with mcp-register).
pub use crate::broker_socket_path;

/// How often the broker re-discovers live registries.
const DEFAULT_RECONCILE: Duration = Duration::from_secs(1);
/// Exit after this long with zero live registries (= no clients running).
const DEFAULT_IDLE_GRACE: Duration = Duration::from_secs(30);

/// Read a millisecond duration from `var`, falling back to `default`. Lets tests
/// shrink the reconcile/idle timings without waiting real seconds.
fn duration_from_env(var: &str, default: Duration) -> Duration {
    std::env::var(var)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .map(Duration::from_millis)
        .unwrap_or(default)
}

fn reconcile_interval() -> Duration {
    duration_from_env("HOST_TOOLS_MCP_BROKER_RECONCILE_MS", DEFAULT_RECONCILE)
}

fn idle_grace() -> Duration {
    duration_from_env("HOST_TOOLS_MCP_BROKER_IDLE_MS", DEFAULT_IDLE_GRACE)
}

/// Bind the front socket, clearing a stale socket file if no live broker holds
/// it. Errors if another broker is already listening.
fn bind_listener(path: &Path) -> Result<UnixListener> {
    match UnixListener::bind(path) {
        Ok(listener) => Ok(listener),
        Err(error) if error.kind() == std::io::ErrorKind::AddrInUse => {
            if std::os::unix::net::UnixStream::connect(path).is_ok() {
                anyhow::bail!("another broker is already listening at {}", path.display());
            }
            // stale socket from a crashed broker: remove and retry once.
            std::fs::remove_file(path)
                .with_context(|| format!("removing stale socket {}", path.display()))?;
            UnixListener::bind(path).with_context(|| format!("binding {}", path.display()))
        }
        Err(error) => {
            Err(anyhow::Error::from(error)).with_context(|| format!("binding {}", path.display()))
        }
    }
}

/// Run the broker until it idle-exits (no live registries for [`IDLE_GRACE`]).
pub async fn run_broker(socket_path: PathBuf) -> Result<()> {
    if let Some(parent) = socket_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let listener = bind_listener(&socket_path)?;
    // Only the local user should reach the bridge.
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(&socket_path, std::fs::Permissions::from_mode(0o600));
    debug_log(format!("broker listening at {}", socket_path.display()));

    let reconcile = reconcile_interval();
    let mut idle = IdleMonitor::new(idle_grace());
    let mut tick = tokio::time::interval(reconcile);
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let (stream, _) = accepted.context("accept on broker socket")?;
                debug_log("broker: downstream provider connected");
                tokio::spawn(handle_downstream(stream, reconcile));
            }
            _ = tick.tick() => {
                let empty = discover_live_servers().map(|s| s.is_empty()).unwrap_or(true);
                if idle.update(empty) {
                    debug_log("broker: no live registries; idle-exiting");
                    break;
                }
            }
        }
    }
    let _ = std::fs::remove_file(&socket_path);
    Ok(())
}

/// Tracks how long the registry set has been empty, to drive idle-exit.
struct IdleMonitor {
    empty_since: Option<Instant>,
    grace: Duration,
}

impl IdleMonitor {
    fn new(grace: Duration) -> Self {
        Self { empty_since: None, grace }
    }

    /// Record the latest emptiness; returns `true` once empty for `grace`.
    fn update(&mut self, empty: bool) -> bool {
        if empty {
            let since = *self.empty_since.get_or_insert_with(Instant::now);
            since.elapsed() >= self.grace
        } else {
            self.empty_since = None;
            false
        }
    }
}

/// Translates between a downstream's single `call_id` space and the per-upstream
/// `call_id` spaces. `cid_f` = front (downstream-facing) id; `cid_u` = the
/// upstream's own id.
#[derive(Default)]
struct CallRouter {
    next: u64,
    fwd: HashMap<String, (u64, String)>,
    rev: HashMap<(u64, String), String>,
}

impl CallRouter {
    fn new() -> Self {
        Self::default()
    }

    /// Allocate (or reuse) a downstream-facing id for an upstream call.
    fn register_call(&mut self, upstream_id: u64, cid_u: String) -> String {
        let key = (upstream_id, cid_u);
        if let Some(existing) = self.rev.get(&key) {
            return existing.clone();
        }
        let cid_f = format!("b{}", self.next);
        self.next += 1;
        self.fwd.insert(cid_f.clone(), key.clone());
        self.rev.insert(key, cid_f.clone());
        cid_f
    }

    /// Resolve and CONSUME the mapping for a completed call (result path).
    fn resolve_result(&mut self, cid_f: &str) -> Option<(u64, String)> {
        let (upstream_id, cid_u) = self.fwd.remove(cid_f)?;
        self.rev.remove(&(upstream_id, cid_u.clone()));
        Some((upstream_id, cid_u))
    }

    /// Resolve without consuming (progress path — more updates may follow).
    fn resolve_keep(&self, cid_f: &str) -> Option<(u64, String)> {
        self.fwd.get(cid_f).cloned()
    }

    /// Reverse lookup for cancellation (upstream -> downstream-facing id).
    fn cid_f_for(&self, upstream_id: u64, cid_u: &str) -> Option<String> {
        self.rev.get(&(upstream_id, cid_u.to_string())).cloned()
    }

    /// Drop every mapping for an upstream that went away.
    fn drop_upstream(&mut self, upstream_id: u64) {
        let stale: Vec<String> = self
            .fwd
            .iter()
            .filter(|(_, (uid, _))| *uid == upstream_id)
            .map(|(cid_f, _)| cid_f.clone())
            .collect();
        for cid_f in stale {
            if let Some((uid, cid_u)) = self.fwd.remove(&cid_f) {
                self.rev.remove(&(uid, cid_u));
            }
        }
    }
}

/// A message that originated from a downstream provider connection.
enum DownstreamMsg {
    Msg(ProviderToServer),
    Closed,
}

/// An event from an upstream relay, tagged with which upstream it came from.
enum RelayEvent {
    FromUpstream { upstream_id: u64, msg: ServerToProvider },
    Closed { upstream_id: u64 },
}

/// Handle to a live upstream relay (one per registry, for this downstream).
struct RelayHandle {
    dir: PathBuf,
    to_upstream: mpsc::Sender<ProviderToServer>,
    join: tokio::task::JoinHandle<()>,
}

/// Serialize one protocol message as a newline-delimited JSON frame.
fn frame<T: serde::Serialize>(message: &T) -> std::io::Result<Vec<u8>> {
    let mut payload = serde_json::to_vec(message).map_err(std::io::Error::other)?;
    payload.push(b'\n');
    Ok(payload)
}

async fn send_to_downstream(
    writer: &mut OwnedWriteHalf,
    message: &ServerToProvider,
) -> std::io::Result<()> {
    writer.write_all(&frame(message)?).await
}

/// Read newline-delimited `ProviderToServer` frames from a downstream provider
/// and forward them to the handler. Kept off the handler's `select!` because
/// `read_line` is not cancellation-safe.
async fn downstream_reader(reader: OwnedReadHalf, tx: mpsc::UnboundedSender<DownstreamMsg>) {
    let mut reader = BufReader::new(reader);
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line).await {
            Ok(0) => break,
            Ok(_) => match serde_json::from_str::<ProviderToServer>(line.trim_end()) {
                Ok(message) => {
                    if tx.send(DownstreamMsg::Msg(message)).is_err() {
                        return;
                    }
                }
                Err(_) => break,
            },
            Err(_) => break,
        }
    }
    let _ = tx.send(DownstreamMsg::Closed);
}

/// One relay: connect to an upstream registry as a provider, pump messages we're
/// told to send, and forward everything the registry sends back to the handler.
async fn relay_task(
    upstream_id: u64,
    socket_path: PathBuf,
    mut to_upstream: mpsc::Receiver<ProviderToServer>,
    events: mpsc::UnboundedSender<RelayEvent>,
) {
    let stream = match UnixStream::connect(&socket_path).await {
        Ok(stream) => stream,
        Err(error) => {
            debug_log(format!(
                "broker: relay connect to {} failed: {error}",
                socket_path.display()
            ));
            let _ = events.send(RelayEvent::Closed { upstream_id });
            return;
        }
    };
    let (reader, mut writer) = stream.into_split();

    // Writer subtask: drains `to_upstream` until the handler drops the Sender
    // (which is how a removed relay is shut down -> the registry sees EOF and
    // deregisters our tools).
    let writer_task = tokio::spawn(async move {
        while let Some(message) = to_upstream.recv().await {
            let payload = match frame(&message) {
                Ok(payload) => payload,
                Err(_) => break,
            };
            if writer.write_all(&payload).await.is_err() {
                break;
            }
        }
    });

    let mut reader = BufReader::new(reader);
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line).await {
            Ok(0) => break,
            Ok(_) => match serde_json::from_str::<ServerToProvider>(line.trim_end()) {
                Ok(msg) => {
                    if events
                        .send(RelayEvent::FromUpstream { upstream_id, msg })
                        .is_err()
                    {
                        break;
                    }
                }
                Err(_) => break,
            },
            Err(_) => break,
        }
    }
    writer_task.abort();
    let _ = events.send(RelayEvent::Closed { upstream_id });
}

/// Drive one downstream provider: own its routing state, fan its tools out to
/// every live registry, and relay calls/results with id translation.
async fn handle_downstream(stream: UnixStream, reconcile_every: Duration) {
    let (reader, mut writer) = stream.into_split();
    let (down_tx, mut down_rx) = mpsc::unbounded_channel::<DownstreamMsg>();
    let (events_tx, mut events_rx) = mpsc::unbounded_channel::<RelayEvent>();
    tokio::spawn(downstream_reader(reader, down_tx));

    let mut tools: Vec<Tool> = Vec::new();
    let mut relays: HashMap<u64, RelayHandle> = HashMap::new();
    let mut dirs: HashMap<PathBuf, u64> = HashMap::new();
    let mut router = CallRouter::new();
    let mut next_upstream_id: u64 = 0;
    let mut tick = tokio::time::interval(reconcile_every);

    loop {
        tokio::select! {
            down = down_rx.recv() => {
                let Some(down) = down else { break };
                match down {
                    DownstreamMsg::Closed => break,
                    DownstreamMsg::Msg(message) => match message {
                        ProviderToServer::RegisterTools { id, tools: new_tools } => {
                            tools = new_tools;
                            if send_to_downstream(&mut writer, &ServerToProvider::Success { in_reply_to: id }).await.is_err() {
                                break;
                            }
                            for relay in relays.values() {
                                let _ = relay.to_upstream.send(ProviderToServer::RegisterTools { id: 1, tools: tools.clone() }).await;
                            }
                        }
                        ProviderToServer::DeregisterTools { id, tools: names } => {
                            tools.retain(|tool| !names.iter().any(|name| tool.name.as_ref() == name));
                            if send_to_downstream(&mut writer, &ServerToProvider::Success { in_reply_to: id }).await.is_err() {
                                break;
                            }
                            for relay in relays.values() {
                                let _ = relay.to_upstream.send(ProviderToServer::DeregisterTools { id: 1, tools: names.clone() }).await;
                            }
                        }
                        ProviderToServer::ToolCallResult { call_id, result } => {
                            if let Some((upstream_id, cid_u)) = router.resolve_result(&call_id) {
                                if let Some(relay) = relays.get(&upstream_id) {
                                    let _ = relay.to_upstream.send(ProviderToServer::ToolCallResult { call_id: cid_u, result }).await;
                                }
                            }
                        }
                        ProviderToServer::ToolCallProgress { call_id, progress, total, message } => {
                            if let Some((upstream_id, cid_u)) = router.resolve_keep(&call_id) {
                                if let Some(relay) = relays.get(&upstream_id) {
                                    let _ = relay.to_upstream.send(ProviderToServer::ToolCallProgress { call_id: cid_u, progress, total, message }).await;
                                }
                            }
                        }
                    }
                }
            }
            event = events_rx.recv() => {
                let Some(event) = event else { continue };
                match event {
                    RelayEvent::FromUpstream { upstream_id, msg } => match msg {
                        ServerToProvider::CallTool { call_id, tool, arguments } => {
                            let cid_f = router.register_call(upstream_id, call_id);
                            if send_to_downstream(&mut writer, &ServerToProvider::CallTool { call_id: cid_f, tool, arguments }).await.is_err() {
                                break;
                            }
                        }
                        ServerToProvider::CancelCall { call_id, reason } => {
                            if let Some(cid_f) = router.cid_f_for(upstream_id, &call_id) {
                                let _ = send_to_downstream(&mut writer, &ServerToProvider::CancelCall { call_id: cid_f, reason }).await;
                            }
                        }
                        // Registration acks from upstreams are not forwarded.
                        ServerToProvider::Success { .. } | ServerToProvider::Error { .. } => {}
                    },
                    RelayEvent::Closed { upstream_id } => {
                        if let Some(relay) = relays.remove(&upstream_id) {
                            relay.join.abort();
                            dirs.remove(&relay.dir);
                        }
                        router.drop_upstream(upstream_id);
                    }
                }
            }
            _ = tick.tick() => {
                let servers = discover_live_servers().unwrap_or_default();
                reconcile(&servers, &mut dirs, &mut relays, &mut router, &mut next_upstream_id, &tools, &events_tx).await;
            }
        }
    }

    // Downstream gone: drop every relay so the registries see EOF and deregister.
    for (_, relay) in relays {
        relay.join.abort();
    }
}

/// Add relays for newly-seen registries and drop relays for ones that vanished.
async fn reconcile(
    servers: &[LiveServer],
    dirs: &mut HashMap<PathBuf, u64>,
    relays: &mut HashMap<u64, RelayHandle>,
    router: &mut CallRouter,
    next_upstream_id: &mut u64,
    tools: &[Tool],
    events_tx: &mpsc::UnboundedSender<RelayEvent>,
) {
    let live: HashSet<&PathBuf> = servers.iter().map(|s| &s.dir).collect();

    for server in servers {
        if dirs.contains_key(&server.dir) {
            continue;
        }
        let upstream_id = *next_upstream_id;
        *next_upstream_id += 1;
        let (tx, rx) = mpsc::channel::<ProviderToServer>(64);
        let join = tokio::spawn(relay_task(
            upstream_id,
            server.socket_path.clone(),
            rx,
            events_tx.clone(),
        ));
        if !tools.is_empty() {
            let _ = tx
                .send(ProviderToServer::RegisterTools { id: 1, tools: tools.to_vec() })
                .await;
        }
        dirs.insert(server.dir.clone(), upstream_id);
        relays.insert(upstream_id, RelayHandle { dir: server.dir.clone(), to_upstream: tx, join });
        debug_log(format!("broker: relay opened for {}", server.dir.display()));
    }

    let gone: Vec<PathBuf> = dirs
        .keys()
        .filter(|dir| !live.contains(*dir))
        .cloned()
        .collect();
    for dir in gone {
        if let Some(upstream_id) = dirs.remove(&dir) {
            if let Some(relay) = relays.remove(&upstream_id) {
                relay.join.abort();
            }
            router.drop_upstream(upstream_id);
            debug_log(format!("broker: relay closed for {}", dir.display()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{CallRouter, IdleMonitor, DEFAULT_IDLE_GRACE};
    use std::time::{Duration, Instant};

    #[test]
    fn router_translates_and_consumes_on_result() {
        let mut router = CallRouter::new();
        let a = router.register_call(7, "1".into());
        let b = router.register_call(9, "1".into()); // same cid_u, different upstream
        assert_ne!(a, b, "distinct upstreams must get distinct front ids");

        // progress keeps the mapping; result consumes it.
        assert_eq!(router.resolve_keep(&a), Some((7, "1".to_string())));
        assert_eq!(router.resolve_result(&a), Some((7, "1".to_string())));
        assert_eq!(router.resolve_result(&a), None, "result must consume mapping");
        assert_eq!(router.resolve_keep(&b), Some((9, "1".to_string())));
    }

    #[test]
    fn router_reuses_front_id_for_same_call() {
        let mut router = CallRouter::new();
        let first = router.register_call(1, "x".into());
        let again = router.register_call(1, "x".into());
        assert_eq!(first, again);
        assert_eq!(router.cid_f_for(1, "x"), Some(first));
    }

    #[test]
    fn router_drop_upstream_clears_its_calls() {
        let mut router = CallRouter::new();
        let a = router.register_call(1, "1".into());
        let _b = router.register_call(2, "1".into());
        router.drop_upstream(1);
        assert_eq!(router.resolve_keep(&a), None);
        assert!(router.cid_f_for(2, "1").is_some(), "other upstream untouched");
    }

    #[test]
    fn idle_monitor_fires_only_after_grace() {
        let mut idle = IdleMonitor::new(DEFAULT_IDLE_GRACE);
        assert!(!idle.update(false));
        // first empty observation starts the clock, does not fire yet.
        assert!(!idle.update(true));
        // a non-empty observation resets it.
        assert!(!idle.update(false));
        assert!(idle.empty_since.is_none());

        // simulate the grace having elapsed.
        idle.empty_since = Some(Instant::now() - DEFAULT_IDLE_GRACE - Duration::from_secs(1));
        assert!(idle.update(true), "should fire once empty for the grace period");
    }
}
