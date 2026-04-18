use std::collections::BTreeSet;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use host_tools_mcp::log_root;
use rand::random;
use serde_json::{json, Value};

const DEFAULT_TIMEOUT: Duration = Duration::from_millis(1500);
const FILE_TIMEOUT: Duration = Duration::from_millis(1000);

fn gen_test_id() -> String {
    format!("{:032x}", random::<u128>())
}

fn base_tmpdir() -> PathBuf {
    std::env::var("TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir())
        .join("ht-mcp")
}

fn test_tmpdir(test_id: &str) -> PathBuf {
    base_tmpdir().join(test_id)
}

fn test_log_root(test_id: &str) -> PathBuf {
    test_tmpdir(test_id).join(
        log_root()
            .file_name()
            .expect("host-tools-mcp root should have a final path component"),
    )
}

struct TestDir {
    tmpdir: PathBuf,
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.tmpdir);
    }
}

fn test_dir(test_id: &str) -> TestDir {
    let tmpdir = test_tmpdir(test_id);
    fs::create_dir_all(&tmpdir).expect("failed to create test tmpdir");
    TestDir { tmpdir }
}

struct ChildHarness {
    child: Child,
    process_dir: PathBuf,
    stdin: ChildStdin,
    stdout_rx: Receiver<Value>,
    reader_handle: Option<JoinHandle<()>>,
}

impl ChildHarness {
    fn spawn(test_id: &str) -> Self {
        let tmpdir = test_tmpdir(test_id);
        let existing_dirs = server_dirs(test_id);
        fs::create_dir_all(&tmpdir).expect("failed to create test TMPDIR");
        let mut child = Command::new(env!("CARGO_BIN_EXE_host-tools-mcp"))
            .env("TMPDIR", &tmpdir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("failed to spawn host-tools-mcp");
        let process_dir = wait_for_new_server_dir(test_id, &existing_dirs);
        let stdin = child.stdin.take().expect("missing child stdin");
        let stdout = child.stdout.take().expect("missing child stdout");
        let (stdout_tx, stdout_rx) = mpsc::channel();
        let reader_handle = thread::spawn(move || {
            let mut stdout = BufReader::new(stdout);
            loop {
                let mut line = String::new();
                match stdout.read_line(&mut line) {
                    Ok(0) => break,
                    Ok(_) => {
                        let message = serde_json::from_str::<Value>(line.trim_end())
                            .expect("invalid child stdout JSON");
                        if stdout_tx.send(message).is_err() {
                            break;
                        }
                    }
                    Err(error) => panic!("failed to read child stdout: {error}"),
                }
            }
        });

        Self {
            child,
            process_dir,
            stdin,
            stdout_rx,
            reader_handle: Some(reader_handle),
        }
    }

    fn process_dir(&self) -> PathBuf {
        self.process_dir.clone()
    }

    fn socket_path(&self) -> PathBuf {
        self.process_dir().join("registry.sock")
    }

    fn send_json_rpc(&mut self, message: Value) {
        serde_json::to_writer(&mut self.stdin, &message).expect("failed to write request");
        self.stdin
            .write_all(b"\n")
            .expect("failed to write newline");
        self.stdin.flush().expect("failed to flush request");
    }

    fn recv_message_timeout(&self, timeout: Duration) -> Option<Value> {
        self.stdout_rx.recv_timeout(timeout).ok()
    }

    fn recv_matching(&self, timeout: Duration, predicate: impl Fn(&Value) -> bool) -> Value {
        let deadline = Instant::now() + timeout;
        while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
            let message = self
                .recv_message_timeout(remaining)
                .expect("timed out waiting for child message");
            if predicate(&message) {
                return message;
            }
        }
        panic!("timed out waiting for matching child message");
    }
}

impl Drop for ChildHarness {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        if let Some(handle) = self.reader_handle.take() {
            let _ = handle.join();
        }
    }
}

struct ProviderHarness {
    stream: UnixStream,
    rx: Receiver<Value>,
    reader_handle: Option<JoinHandle<()>>,
}

impl ProviderHarness {
    fn connect(socket_path: &Path) -> Self {
        let stream = UnixStream::connect(socket_path).expect("failed to connect provider socket");
        let reader = stream.try_clone().expect("failed to clone provider stream");
        let (tx, rx) = mpsc::channel();
        let reader_handle = thread::spawn(move || {
            let mut reader = BufReader::new(reader);
            loop {
                let mut line = String::new();
                match reader.read_line(&mut line) {
                    Ok(0) => break,
                    Ok(_) => {
                        let message = serde_json::from_str::<Value>(line.trim_end())
                            .expect("invalid provider message JSON");
                        if tx.send(message).is_err() {
                            break;
                        }
                    }
                    Err(error) => panic!("failed to read provider message: {error}"),
                }
            }
        });

        Self {
            stream,
            rx,
            reader_handle: Some(reader_handle),
        }
    }

    fn send(&mut self, message: Value) {
        serde_json::to_writer(&mut self.stream, &message)
            .expect("failed to write provider message");
        self.stream
            .write_all(b"\n")
            .expect("failed to write provider newline");
        self.stream
            .flush()
            .expect("failed to flush provider message");
    }

    fn send_raw(&mut self, raw: &str) {
        self.stream
            .write_all(raw.as_bytes())
            .expect("failed to write raw provider payload");
        self.stream
            .write_all(b"\n")
            .expect("failed to write raw provider newline");
        self.stream
            .flush()
            .expect("failed to flush raw provider payload");
    }

    fn recv_timeout(&self, timeout: Duration) -> Option<Value> {
        self.rx.recv_timeout(timeout).ok()
    }

    fn recv_matching(&self, timeout: Duration, predicate: impl Fn(&Value) -> bool) -> Value {
        let deadline = Instant::now() + timeout;
        while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
            let message = self
                .recv_timeout(remaining)
                .expect("timed out waiting for provider message");
            if predicate(&message) {
                return message;
            }
        }
        panic!("timed out waiting for matching provider message");
    }
}

impl Drop for ProviderHarness {
    fn drop(&mut self) {
        let _ = self.stream.shutdown(std::net::Shutdown::Both);
        if let Some(handle) = self.reader_handle.take() {
            let _ = handle.join();
        }
    }
}

#[test]
fn startup_creates_artifacts_and_empty_tool_list() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    wait_for_file(&child.process_dir().join("server.log"));

    initialize_client(&mut child);
    child.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/list"
    }));
    let response = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(1));
    assert_eq!(response["result"]["tools"], json!([]));

    assert!(child
        .process_dir()
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| {
            name.chars()
                .all(|ch| ch.is_ascii_digit() || matches!(ch, '-' | '_' | '+' | '.'))
        }));
}

#[test]
fn provider_log_is_created_after_connect() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());

    let _provider = ProviderHarness::connect(&child.socket_path());
    wait_for_file(&child.process_dir().join("tool-provider-1.log"));
}

#[test]
fn registers_tools_calls_them_and_logs_provider_messages() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    assert_eq!(list_tools(&mut child)[0]["name"], json!("ping"));

    call_tool(
        &mut child,
        2,
        json!({
            "_meta": {"progressToken": 7},
            "name": "ping",
            "arguments": {"message": "hello"}
        }),
    );

    let call_message =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool");
    let call_id = call_message["callId"]
        .as_str()
        .expect("missing callId")
        .to_string();
    assert_eq!(call_message["tool"], json!("ping"));

    provider.send(json!({
        "type": "tool_call_progress",
        "callId": call_id,
        "progress": 1.0,
        "total": 2.0,
        "message": "step 1"
    }));
    let progress = child.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/progress"
    });
    assert_eq!(progress["params"]["progressToken"], json!(7));
    assert_eq!(progress["params"]["message"], json!("step 1"));

    provider.send(json!({
        "type": "tool_call_result",
        "callId": call_message["callId"],
        "result": {
            "content": [{"type": "text", "text": "provider says hello"}],
            "isError": false
        }
    }));
    let result = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(
        result["result"]["content"][0]["text"],
        json!("provider says hello")
    );

    let provider_log = read_json_lines(&child.process_dir().join("tool-provider-1.log"));
    assert!(provider_log
        .iter()
        .any(|line| line["direction"] == "in" && line["message"]["type"] == "register_tools"));
    assert!(provider_log
        .iter()
        .any(|line| line["direction"] == "out" && line["message"]["type"] == "success"));
    assert!(provider_log
        .iter()
        .any(|line| line["direction"] == "out" && line["message"]["type"] == "call_tool"));
    assert!(provider_log
        .iter()
        .any(|line| line["direction"] == "in" && line["message"]["type"] == "tool_call_progress"));
    assert!(provider_log
        .iter()
        .any(|line| line["direction"] == "in" && line["message"]["type"] == "tool_call_result"));
}

#[test]
fn rejects_duplicate_tool_registration_and_duplicate_names_in_batch() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider_a = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider_a, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    let mut provider_b = ProviderHarness::connect(&child.socket_path());
    provider_b.send(json!({
        "type": "register_tools",
        "id": 1,
        "tools": [tool_definition("ping")]
    }));
    let error = provider_b.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "error");
    assert!(error["message"]
        .as_str()
        .unwrap_or_default()
        .contains("already exists"));

    provider_b.send(json!({
        "type": "register_tools",
        "id": 2,
        "tools": [tool_definition("dup"), tool_definition("dup")]
    }));
    let error = provider_b.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["type"] == "error" && message["inReplyTo"] == json!(2)
    });
    assert!(error["message"]
        .as_str()
        .unwrap_or_default()
        .contains("appears multiple times"));
}

#[test]
fn supports_multiple_tools_and_partial_deregistration() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(
        &mut provider,
        1,
        &[tool_definition("ping"), tool_definition("pong")],
    );
    expect_tool_list_changed(&child);

    let tools = list_tools(&mut child);
    assert_eq!(
        tool_names(&tools),
        vec!["ping".to_string(), "pong".to_string()]
    );

    call_tool(&mut child, 2, tool_call_params("ping", "hello"));
    let ping_call = provider.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["type"] == "call_tool" && message["tool"] == "ping"
    });

    provider.send(json!({
        "type": "deregister_tools",
        "id": 2,
        "tools": ["ping"]
    }));
    let cancel =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "cancel_call");
    assert_eq!(cancel["callId"], ping_call["callId"]);
    let _ = provider.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["type"] == "success" && message["inReplyTo"] == json!(2)
    });

    let (response, list_changed) = recv_call_response_and_list_changed(&child, json!(2));
    assert!(response.get("error").is_some());
    assert_eq!(
        list_changed["method"],
        json!("notifications/tools/list_changed")
    );

    let tools = list_tools(&mut child);
    assert_eq!(tool_names(&tools), vec!["pong".to_string()]);

    call_tool(&mut child, 3, tool_call_params("pong", "world"));
    let pong_call = provider.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["type"] == "call_tool" && message["tool"] == "pong"
    });
    provider.send(json!({
        "type": "tool_call_result",
        "callId": pong_call["callId"],
        "result": {
            "content": [{"type": "text", "text": "pong ok"}],
            "isError": false
        }
    }));
    let response = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(3));
    assert_eq!(response["result"]["content"][0]["text"], json!("pong ok"));
}

#[test]
fn provider_sent_error_result_is_forwarded_as_tool_result() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    call_tool(&mut child, 2, tool_call_params("ping", "hello"));
    let call_message =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool");
    provider.send(json!({
        "type": "tool_call_result",
        "callId": call_message["callId"],
        "result": {
            "content": [{"type": "text", "text": "provider failed"}],
            "isError": true
        }
    }));

    let response = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["isError"], json!(true));
    assert_eq!(
        response["result"]["content"][0]["text"],
        json!("provider failed")
    );
}

#[test]
fn client_cancellation_forwards_cancel_call_to_provider() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    call_tool(&mut child, 2, tool_call_params("ping", "hello"));
    let call_message =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool");

    child.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": {
            "requestId": 2,
            "reason": "client timed out"
        }
    }));

    let cancel =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "cancel_call");
    assert_eq!(cancel["callId"], call_message["callId"]);
    assert_eq!(cancel["reason"], json!("client timed out"));
}

#[test]
fn ignores_unknown_call_ids_without_breaking_real_calls() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    provider.send(json!({
        "type": "tool_call_progress",
        "callId": "missing",
        "progress": 1.0,
        "total": 1.0,
        "message": "ghost"
    }));
    provider.send(json!({
        "type": "tool_call_result",
        "callId": "missing",
        "result": {
            "content": [{"type": "text", "text": "ghost"}],
            "isError": false
        }
    }));
    call_tool(&mut child, 2, tool_call_params("ping", "hello"));
    let call_message =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool");
    provider.send(json!({
        "type": "tool_call_result",
        "callId": call_message["callId"],
        "result": {
            "content": [{"type": "text", "text": "real"}],
            "isError": false
        }
    }));
    let response = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["content"][0]["text"], json!("real"));
}

#[test]
fn ignores_progress_updates_when_client_did_not_request_progress() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    call_tool(&mut child, 2, tool_call_params("ping", "hello"));
    let call_message =
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool");
    provider.send(json!({
        "type": "tool_call_progress",
        "callId": call_message["callId"],
        "progress": 1.0,
        "total": 1.0,
        "message": "should be ignored"
    }));
    provider.send(json!({
        "type": "tool_call_result",
        "callId": call_message["callId"],
        "result": {
            "content": [{"type": "text", "text": "real"}],
            "isError": false
        }
    }));

    let response = child.recv_matching(DEFAULT_TIMEOUT, |message| {
        assert_ne!(message["method"], json!("notifications/progress"));
        message["id"] == json!(2)
    });
    assert_eq!(response["result"]["content"][0]["text"], json!("real"));
}

#[test]
fn malformed_provider_json_disconnects_the_provider() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut malformed = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut malformed, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);
    malformed.send_raw("not-json");
    wait_for_tools(&mut child, &[]);

    let mut replacement = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut replacement, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);
    wait_for_tools(&mut child, &["ping"]);
}

#[test]
fn unknown_provider_messages_disconnect_the_provider() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    provider.send(json!({
        "type": "unknown_message",
        "id": 2
    }));
    wait_for_tools(&mut child, &[]);

    let mut replacement = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut replacement, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);
    wait_for_tools(&mut child, &["ping"]);
}

#[test]
fn deregistering_unknown_or_unowned_tools_returns_errors() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider_a = ProviderHarness::connect(&child.socket_path());
    let mut provider_b = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider_a, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    provider_b.send(json!({
        "type": "deregister_tools",
        "id": 1,
        "tools": ["ping"]
    }));
    let error = provider_b.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "error");
    assert!(error["message"]
        .as_str()
        .unwrap_or_default()
        .contains("not registered by provider"));

    provider_a.send(json!({
        "type": "deregister_tools",
        "id": 2,
        "tools": ["missing"]
    }));
    let error = provider_a.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["type"] == "error" && message["inReplyTo"] == json!(2)
    });
    assert!(error["message"]
        .as_str()
        .unwrap_or_default()
        .contains("not registered by provider"));
}

#[test]
fn reconnecting_provider_can_reuse_a_tool_name_after_disconnect() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider_a = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider_a, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);
    drop(provider_a);
    wait_for_tools(&mut child, &[]);

    let mut provider_b = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider_b, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);
    wait_for_tools(&mut child, &["ping"]);
}

#[test]
fn concurrent_calls_get_distinct_provider_call_ids_and_results() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    call_tool(&mut child, 2, tool_call_params("ping", "first"));
    call_tool(&mut child, 3, tool_call_params("ping", "second"));

    let provider_calls = vec![
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool"),
        provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool"),
    ];
    assert_ne!(provider_calls[0]["callId"], provider_calls[1]["callId"]);

    for provider_call in provider_calls.iter().rev() {
        let message = provider_call["arguments"]["message"]
            .as_str()
            .expect("missing provider call message");
        provider.send(json!({
            "type": "tool_call_result",
            "callId": provider_call["callId"],
            "result": {
                "content": [{"type": "text", "text": format!("{message} result")}],
                "isError": false
            }
        }));
    }

    let responses = recv_call_responses(&child, &[2, 3]);
    assert!(responses.iter().any(|response| response["id"] == json!(2)
        && response["result"]["content"][0]["text"] == json!("first result")));
    assert!(responses.iter().any(|response| response["id"] == json!(3)
        && response["result"]["content"][0]["text"] == json!("second result")));
}

#[test]
fn disconnecting_a_provider_unregisters_tools_and_cancels_calls() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut child = ChildHarness::spawn(&test_id);
    wait_for_file(&child.socket_path());
    initialize_client(&mut child);

    let mut provider = ProviderHarness::connect(&child.socket_path());
    register_tools(&mut provider, 1, &[tool_definition("ping")]);
    expect_tool_list_changed(&child);

    call_tool(&mut child, 2, tool_call_params("ping", "hello"));
    let _ = provider.recv_matching(DEFAULT_TIMEOUT, |message| message["type"] == "call_tool");
    drop(provider);

    let (response, list_changed) = recv_call_response_and_list_changed(&child, json!(2));
    assert!(response.get("error").is_some());
    assert_eq!(
        list_changed["method"],
        json!("notifications/tools/list_changed")
    );
    assert_eq!(list_tools(&mut child), Vec::<Value>::new());
}

fn initialize_client(child: &mut ChildHarness) {
    child.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {
                "name": "e2e-test",
                "version": "0.1.0"
            }
        }
    }));
    let initialize = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(0));
    assert!(initialize["result"]["capabilities"]["tools"].is_object());
    child.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "method": "notifications/initialized"
    }));
}

fn register_tools(provider: &mut ProviderHarness, id: u64, tools: &[Value]) {
    provider.send(json!({
        "type": "register_tools",
        "id": id,
        "tools": tools
    }));
    let success = provider.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["type"] == "success" && message["inReplyTo"] == json!(id)
    });
    assert_eq!(success, json!({"type":"success","inReplyTo":id}));
}

fn expect_tool_list_changed(child: &ChildHarness) -> Value {
    child.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/tools/list_changed"
    })
}

fn list_tools(child: &mut ChildHarness) -> Vec<Value> {
    child.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": 99,
        "method": "tools/list"
    }));
    let response = child.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(99));
    response["result"]["tools"]
        .as_array()
        .cloned()
        .unwrap_or_default()
}

fn call_tool(child: &mut ChildHarness, id: i64, params: Value) {
    child.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": "tools/call",
        "params": params
    }));
}

fn tool_call_params(name: &str, message: &str) -> Value {
    json!({
        "name": name,
        "arguments": {"message": message}
    })
}

fn tool_definition(name: &str) -> Value {
    json!({
        "name": name,
        "description": format!("{name} tool"),
        "inputSchema": {
            "type": "object",
            "properties": {
                "message": {"type": "string"}
            },
            "required": ["message"]
        }
    })
}

fn tool_names(tools: &[Value]) -> Vec<String> {
    let mut names = tools
        .iter()
        .map(|tool| {
            tool["name"]
                .as_str()
                .expect("missing tool name")
                .to_string()
        })
        .collect::<Vec<_>>();
    names.sort();
    names
}

fn wait_for_tools(child: &mut ChildHarness, expected: &[&str]) {
    let deadline = Instant::now() + DEFAULT_TIMEOUT;
    let mut expected = expected
        .iter()
        .map(|name| (*name).to_string())
        .collect::<Vec<_>>();
    expected.sort();

    let mut last_seen = Vec::new();
    while Instant::now() < deadline {
        last_seen = tool_names(&list_tools(child));
        if last_seen == expected {
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }

    panic!(
        "timed out waiting for expected tool set: expected {:?}, got {:?}",
        expected, last_seen
    );
}

fn wait_for_file(path: &Path) {
    let deadline = Instant::now() + FILE_TIMEOUT;
    while Instant::now() < deadline {
        if path.exists() {
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("timed out waiting for {}", path.display());
}

fn read_json_lines(path: &Path) -> Vec<Value> {
    let deadline = Instant::now() + FILE_TIMEOUT;
    loop {
        let content = fs::read_to_string(path).expect("failed to read log file");
        let parsed = content
            .lines()
            .map(serde_json::from_str::<Value>)
            .collect::<Result<Vec<_>, _>>();
        match parsed {
            Ok(lines) => return lines,
            Err(_) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
            Err(error) => panic!("invalid log JSON: {error}"),
        }
    }
}

fn server_dirs(test_id: &str) -> BTreeSet<PathBuf> {
    fs::read_dir(test_log_root(test_id))
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| path.is_dir())
        .collect()
}

fn wait_for_new_server_dir(test_id: &str, existing_dirs: &BTreeSet<PathBuf>) -> PathBuf {
    let deadline = Instant::now() + FILE_TIMEOUT;
    while Instant::now() < deadline {
        for dir in server_dirs(test_id) {
            if !existing_dirs.contains(&dir) && dir.join("server.log").exists() {
                return dir;
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("timed out waiting for new server directory");
}

fn recv_call_response_and_list_changed(child: &ChildHarness, id: Value) -> (Value, Value) {
    let deadline = Instant::now() + DEFAULT_TIMEOUT;
    let mut response = None;
    let mut list_changed = None;

    while Instant::now() < deadline && (response.is_none() || list_changed.is_none()) {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let message = child
            .recv_message_timeout(remaining)
            .expect("timed out waiting for cancellation messages");
        if message["id"] == id {
            response = Some(message);
        } else if message["method"] == "notifications/tools/list_changed" {
            list_changed = Some(message);
        }
    }

    (
        response.expect("missing call response"),
        list_changed.expect("missing tools/list_changed notification"),
    )
}

fn recv_call_responses(child: &ChildHarness, ids: &[i64]) -> Vec<Value> {
    let deadline = Instant::now() + DEFAULT_TIMEOUT;
    let mut responses = Vec::new();

    while Instant::now() < deadline && responses.len() < ids.len() {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let message = child
            .recv_message_timeout(remaining)
            .expect("timed out waiting for call responses");
        if let Some(id) = message["id"].as_i64() {
            if ids.contains(&id) {
                responses.push(message);
            }
        }
    }

    assert_eq!(
        responses.len(),
        ids.len(),
        "missing expected call responses"
    );
    responses
}
