//! Integration tests for the multiplexing broker.
//!
//! These spawn the real `host-tools-mcp-broker` binary against a private TMPDIR
//! and drive it with fake "registry" servers (the upstream/server side of the
//! protocol) plus a fake downstream provider (what the remote `mcp-register`
//! is). The broker's reconcile/idle timings are shrunk via env vars so the
//! dynamic-watch and idle-exit behaviours are testable in milliseconds.
//!
//! Design note: the broker is single-downstream by intent. Multiple concurrent
//! downstream providers each open their own relay to every registry, so two
//! downstreams registering the same tool name would collide at a real registry
//! server. These tests therefore exercise one downstream at a time.

use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use host_tools_mcp::{ProviderToServer, RegisteredCommand, ServerToProvider};
use serde_json::{json, Map};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::mpsc;
use tokio::time::timeout;

const STEP: Duration = Duration::from_secs(10);
/// Fast reconcile so dynamic watch reacts within a test's patience.
const FAST_RECONCILE_MS: &str = "80";

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn unique_tmpdir() -> PathBuf {
    let base = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let dir = PathBuf::from(base).join(format!("broker-it-{}-{}", std::process::id(), n));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Kills the broker child on drop so a failed assertion never leaks it.
struct BrokerChild(Child);
impl Drop for BrokerChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn spawn_broker(tmp: &Path, extra_env: &[(&str, &str)]) -> BrokerChild {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_host-tools-mcp-broker"));
    cmd.env("TMPDIR", tmp)
        .env("HOST_TOOLS_MCP_BROKER_RECONCILE_MS", FAST_RECONCILE_MS);
    for (k, v) in extra_env {
        cmd.env(k, v);
    }
    BrokerChild(cmd.spawn().expect("failed to spawn broker"))
}

fn broker_sock(tmp: &Path) -> PathBuf {
    // Inside the host-tools-mcp/ dir (matches broker_socket_path()).
    tmp.join("host-tools-mcp").join("broker.sock")
}

async fn send<W: AsyncWriteExt + Unpin, T: serde::Serialize>(writer: &mut W, message: &T) {
    let mut payload = serde_json::to_vec(message).unwrap();
    payload.push(b'\n');
    writer.write_all(&payload).await.unwrap();
}

async fn next_line(lines: &mut Lines<BufReader<OwnedReadHalf>>) -> Option<String> {
    timeout(STEP, lines.next_line())
        .await
        .expect("timed out waiting for a line")
        .expect("read error")
}

async fn wait_for_socket(path: &Path) {
    let deadline = tokio::time::Instant::now() + STEP;
    loop {
        if std::os::unix::net::UnixStream::connect(path).is_ok() {
            return;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "socket {} never became connectable",
            path.display()
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

async fn wait_until_gone(path: &Path) {
    let deadline = tokio::time::Instant::now() + STEP;
    loop {
        if !path.exists() {
            return;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "socket {} still present",
            path.display()
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

// ---- fake upstream registry (server side of the protocol) -------------------

#[derive(Debug, PartialEq)]
enum UpEvent {
    Registered(usize),
    Deregistered(Vec<String>),
    Result(String),
    Progress(String),
    RelayClosed,
}

enum UpCmd {
    Call(String),
    Cancel(String),
    Shutdown,
}

/// Handle to a fake registry running as an actor task.
struct Upstream {
    events: mpsc::UnboundedReceiver<UpEvent>,
    cmds: mpsc::UnboundedSender<UpCmd>,
}

impl Upstream {
    fn start(root: &Path, name: &str) -> Self {
        let dir = root.join(name);
        std::fs::create_dir_all(&dir).unwrap();
        let listener = UnixListener::bind(dir.join("registry.sock")).unwrap();
        let (ev_tx, ev_rx) = mpsc::unbounded_channel();
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        tokio::spawn(upstream_actor(listener, ev_tx, cmd_rx));
        Self { events: ev_rx, cmds: cmd_tx }
    }

    async fn next(&mut self) -> UpEvent {
        timeout(STEP, self.events.recv())
            .await
            .expect("timed out waiting for upstream event")
            .expect("upstream actor ended")
    }

    fn call(&self, call_id: &str) {
        self.cmds.send(UpCmd::Call(call_id.to_string())).unwrap();
    }
    fn cancel(&self, call_id: &str) {
        self.cmds.send(UpCmd::Cancel(call_id.to_string())).unwrap();
    }
    fn shutdown(&self) {
        let _ = self.cmds.send(UpCmd::Shutdown);
    }
}

async fn upstream_actor(
    listener: UnixListener,
    events: mpsc::UnboundedSender<UpEvent>,
    mut cmds: mpsc::UnboundedReceiver<UpCmd>,
) {
    // Find the relay connection, skipping `discover_live_servers` liveness
    // probes (connect + immediate EOF) and honouring an early Shutdown.
    let (mut lines, mut writer) = loop {
        let accept = tokio::select! {
            a = listener.accept() => a,
            cmd = cmds.recv() => {
                if matches!(cmd, Some(UpCmd::Shutdown) | None) { return; }
                continue;
            }
        };
        let Ok((stream, _)) = accept else { return };
        let (reader, writer) = stream.into_split();
        let mut lines = BufReader::new(reader).lines();
        match next_line(&mut lines).await {
            Some(line) => match serde_json::from_str::<ProviderToServer>(&line) {
                Ok(ProviderToServer::RegisterTools { tools, .. }) => {
                    let _ = events.send(UpEvent::Registered(tools.len()));
                    let mut writer = writer;
                    send(&mut writer, &ServerToProvider::Success { in_reply_to: 1 }).await;
                    break (lines, writer);
                }
                _ => continue,
            },
            None => continue, // probe
        }
    };

    // Relay loop: keep `listener` alive so the registry stays discoverable.
    loop {
        tokio::select! {
            line = lines.next_line() => {
                let line = match line { Ok(Some(l)) => l, _ => { let _ = events.send(UpEvent::RelayClosed); return; } };
                match serde_json::from_str::<ProviderToServer>(&line) {
                    Ok(ProviderToServer::ToolCallResult { call_id, .. }) => { let _ = events.send(UpEvent::Result(call_id)); }
                    Ok(ProviderToServer::ToolCallProgress { call_id, .. }) => { let _ = events.send(UpEvent::Progress(call_id)); }
                    Ok(ProviderToServer::DeregisterTools { tools, .. }) => {
                        let _ = events.send(UpEvent::Deregistered(tools));
                        send(&mut writer, &ServerToProvider::Success { in_reply_to: 2 }).await;
                    }
                    Ok(ProviderToServer::RegisterTools { tools, .. }) => {
                        let _ = events.send(UpEvent::Registered(tools.len()));
                        send(&mut writer, &ServerToProvider::Success { in_reply_to: 1 }).await;
                    }
                    Err(_) => {}
                }
            }
            cmd = cmds.recv() => match cmd {
                Some(UpCmd::Call(call_id)) => {
                    send(&mut writer, &ServerToProvider::CallTool { call_id, tool: "sh_c".into(), arguments: Map::new() }).await;
                }
                Some(UpCmd::Cancel(call_id)) => {
                    send(&mut writer, &ServerToProvider::CancelCall { call_id, reason: "test".into() }).await;
                }
                Some(UpCmd::Shutdown) | None => return, // drops listener + relay -> registry disappears
            }
        }
    }
}

// ---- fake downstream provider (what the remote mcp-register is) -------------

struct Downstream {
    lines: Lines<BufReader<OwnedReadHalf>>,
    writer: OwnedWriteHalf,
}

impl Downstream {
    async fn connect(sock: &Path) -> Self {
        let (reader, writer) = UnixStream::connect(sock).await.unwrap().into_split();
        Self { lines: BufReader::new(reader).lines(), writer }
    }

    async fn send(&mut self, message: &ProviderToServer) {
        send(&mut self.writer, message).await;
    }

    async fn recv(&mut self) -> ServerToProvider {
        let line = next_line(&mut self.lines).await.expect("downstream EOF");
        serde_json::from_str(&line).expect("bad ServerToProvider")
    }

    /// Register a prefix tool and await the Success ack; returns the tool name.
    async fn register(&mut self, prefix: &[&str]) -> String {
        let cmd = RegisteredCommand::argv_prefix(prefix.iter().map(|s| s.to_string()).collect())
            .unwrap();
        let name = cmd.tool_name();
        self.send(&ProviderToServer::RegisterTools { id: 1, tools: vec![cmd.tool_definition()] })
            .await;
        match self.recv().await {
            ServerToProvider::Success { .. } => name,
            other => panic!("expected Success, got {other:?}"),
        }
    }
}

fn dummy_result() -> rmcp::model::CallToolResult {
    serde_json::from_value(json!({ "content": [{ "type": "text", "text": "ok" }], "isError": false }))
        .unwrap()
}

// ---- tests ------------------------------------------------------------------

#[tokio::test]
async fn fans_out_and_routes_call_results_back() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let mut u0 = Upstream::start(&root, "u0");
    let mut u1 = Upstream::start(&root, "u1");
    let _broker = spawn_broker(&tmp, &[]);
    wait_for_socket(&broker_sock(&tmp)).await;

    let mut down = Downstream::connect(&broker_sock(&tmp)).await;
    let tool = down.register(&["sh", "-c"]).await;
    assert_eq!(tool, "sh_c");

    // Fan-out: both registries received the registration.
    assert_eq!(u0.next().await, UpEvent::Registered(1));
    assert_eq!(u1.next().await, UpEvent::Registered(1));

    // u0 issues a call -> broker forwards it to the downstream (translated id).
    u0.call("u0-call-1");
    let front_id = match down.recv().await {
        ServerToProvider::CallTool { call_id, tool, .. } => {
            assert_eq!(tool, "sh_c");
            call_id
        }
        other => panic!("expected CallTool, got {other:?}"),
    };
    down.send(&ProviderToServer::ToolCallResult { call_id: front_id, result: dummy_result() })
        .await;

    // Result routed back to u0 under ITS own call_id.
    assert_eq!(u0.next().await, UpEvent::Result("u0-call-1".to_string()));

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn registers_with_late_joining_registry() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let mut u0 = Upstream::start(&root, "u0");
    let _broker = spawn_broker(&tmp, &[]);
    wait_for_socket(&broker_sock(&tmp)).await;

    let mut down = Downstream::connect(&broker_sock(&tmp)).await;
    down.register(&["sh", "-c"]).await;
    assert_eq!(u0.next().await, UpEvent::Registered(1));

    // A registry that appears AFTER registration must still get the tool.
    let mut u_late = Upstream::start(&root, "u-late");
    assert_eq!(
        u_late.next().await,
        UpEvent::Registered(1),
        "late-joining registry should receive the downstream's tools"
    );

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn drops_relay_when_registry_disappears() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let mut u0 = Upstream::start(&root, "u0");
    let mut u1 = Upstream::start(&root, "u1");
    let _broker = spawn_broker(&tmp, &[]);
    wait_for_socket(&broker_sock(&tmp)).await;

    let mut down = Downstream::connect(&broker_sock(&tmp)).await;
    down.register(&["sh", "-c"]).await;
    assert_eq!(u0.next().await, UpEvent::Registered(1));
    assert_eq!(u1.next().await, UpEvent::Registered(1));

    // u1 goes away; the broker must keep serving u0.
    u1.shutdown();
    u0.call("after-removal");
    let front_id = match down.recv().await {
        ServerToProvider::CallTool { call_id, .. } => call_id,
        other => panic!("expected CallTool, got {other:?}"),
    };
    down.send(&ProviderToServer::ToolCallResult { call_id: front_id, result: dummy_result() })
        .await;
    assert_eq!(u0.next().await, UpEvent::Result("after-removal".to_string()));

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn downstream_disconnect_closes_upstream_relays() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let mut u0 = Upstream::start(&root, "u0");
    let _broker = spawn_broker(&tmp, &[]);
    wait_for_socket(&broker_sock(&tmp)).await;

    {
        let mut down = Downstream::connect(&broker_sock(&tmp)).await;
        down.register(&["sh", "-c"]).await;
        assert_eq!(u0.next().await, UpEvent::Registered(1));
        // drop `down` here -> downstream disconnects
    }

    // The registry's relay must close (so the tool deregisters from clients).
    assert_eq!(
        u0.next().await,
        UpEvent::RelayClosed,
        "upstream relay should close when the downstream disconnects"
    );

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn deregister_propagates_to_registries() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let mut u0 = Upstream::start(&root, "u0");
    let _broker = spawn_broker(&tmp, &[]);
    wait_for_socket(&broker_sock(&tmp)).await;

    let mut down = Downstream::connect(&broker_sock(&tmp)).await;
    let tool = down.register(&["sh", "-c"]).await;
    assert_eq!(u0.next().await, UpEvent::Registered(1));

    down.send(&ProviderToServer::DeregisterTools { id: 2, tools: vec![tool.clone()] })
        .await;
    match down.recv().await {
        ServerToProvider::Success { .. } => {}
        other => panic!("expected Success for deregister, got {other:?}"),
    }
    assert_eq!(u0.next().await, UpEvent::Deregistered(vec![tool]));

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn forwards_progress_and_cancellation() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let mut u0 = Upstream::start(&root, "u0");
    let _broker = spawn_broker(&tmp, &[]);
    wait_for_socket(&broker_sock(&tmp)).await;

    let mut down = Downstream::connect(&broker_sock(&tmp)).await;
    down.register(&["sh", "-c"]).await;
    assert_eq!(u0.next().await, UpEvent::Registered(1));

    u0.call("call-x");
    let front_id = match down.recv().await {
        ServerToProvider::CallTool { call_id, .. } => call_id,
        other => panic!("expected CallTool, got {other:?}"),
    };

    // Progress flows downstream->upstream and keeps the mapping alive.
    down.send(&ProviderToServer::ToolCallProgress {
        call_id: front_id.clone(),
        progress: 0.5,
        total: Some(1.0),
        message: Some("half".into()),
    })
    .await;
    assert_eq!(u0.next().await, UpEvent::Progress("call-x".to_string()));

    // Cancellation flows upstream->downstream, translated to the front id.
    u0.cancel("call-x");
    match down.recv().await {
        ServerToProvider::CancelCall { call_id, .. } => assert_eq!(call_id, front_id),
        other => panic!("expected CancelCall, got {other:?}"),
    }

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn ensure_is_a_no_op_when_already_running() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let _u0 = Upstream::start(&root, "u0"); // keep a registry so the broker stays up
    let _broker = spawn_broker(&tmp, &[]);
    let sock = broker_sock(&tmp);
    wait_for_socket(&sock).await;

    // A second `--ensure` invocation should connect, see it's running, exit 0.
    let status = Command::new(env!("CARGO_BIN_EXE_host-tools-mcp-broker"))
        .arg("--ensure")
        .env("TMPDIR", &tmp)
        .status()
        .expect("failed to run --ensure");
    assert!(status.success(), "--ensure should exit 0 when a broker is running");
    // Original broker still listening.
    assert!(std::os::unix::net::UnixStream::connect(&sock).is_ok());

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn recovers_from_a_stale_socket_file() {
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    std::fs::create_dir_all(&root).unwrap();
    // A leftover regular file where the socket should be.
    std::fs::write(broker_sock(&tmp), b"stale").unwrap();

    let _u0 = Upstream::start(&root, "u0"); // keep it alive
    let _broker = spawn_broker(&tmp, &[]);

    // Broker must remove the stale file and bind a real socket we can connect to.
    wait_for_socket(&broker_sock(&tmp)).await;

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn idle_exits_when_no_registries() {
    let tmp = unique_tmpdir();
    // No upstreams at all; short idle grace -> the broker should exit promptly.
    let _broker = spawn_broker(&tmp, &[("HOST_TOOLS_MCP_BROKER_IDLE_MS", "300")]);
    let sock = broker_sock(&tmp);
    wait_for_socket(&sock).await;
    wait_until_gone(&sock).await; // run_broker unlinks the socket on idle-exit

    let _ = std::fs::remove_dir_all(&tmp);
}

#[tokio::test]
async fn broker_socket_is_private() {
    use std::os::unix::fs::PermissionsExt;
    let tmp = unique_tmpdir();
    let root = tmp.join("host-tools-mcp");
    let _u0 = Upstream::start(&root, "u0");
    let _broker = spawn_broker(&tmp, &[]);
    let sock = broker_sock(&tmp);
    wait_for_socket(&sock).await;

    let mode = std::fs::metadata(&sock).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600, "broker socket must be user-private");

    let _ = std::fs::remove_dir_all(&tmp);
}
