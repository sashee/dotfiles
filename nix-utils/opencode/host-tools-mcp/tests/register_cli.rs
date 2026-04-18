use std::collections::BTreeSet;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use host_tools_mcp::{log_root, RegisteredCommand};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use rand::random;
use serde_json::{json, Value};

const DEFAULT_TIMEOUT: Duration = Duration::from_millis(1500);
const FILE_TIMEOUT: Duration = Duration::from_millis(1800);
const EXTENDED_TIMEOUT: Duration = Duration::from_millis(3000);

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
    fn spawn(binary: &str, test_id: &str) -> Self {
        let tmpdir = test_tmpdir(test_id);
        let existing_dirs = server_dirs(test_id);
        fs::create_dir_all(&tmpdir).expect("failed to create test TMPDIR");
        let mut child = Command::new(binary)
            .env("TMPDIR", &tmpdir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("failed to spawn child");
        let process_dir = wait_for_new_server_dir(test_id, &existing_dirs);
        let stdin = child.stdin.take().expect("missing child stdin");
        let stdout = child.stdout.take().expect("missing child stdout");
        let (tx, rx) = mpsc::channel();
        let reader_handle = thread::spawn(move || {
            let mut stdout = BufReader::new(stdout);
            loop {
                let mut line = String::new();
                match stdout.read_line(&mut line) {
                    Ok(0) => break,
                    Ok(_) => {
                        let message = serde_json::from_str::<Value>(line.trim_end())
                            .expect("invalid child JSON");
                        if tx.send(message).is_err() {
                            break;
                        }
                    }
                    Err(error) => panic!("failed reading child stdout: {error}"),
                }
            }
        });

        Self {
            child,
            process_dir,
            stdin,
            stdout_rx: rx,
            reader_handle: Some(reader_handle),
        }
    }

    fn host_tools_mcp(test_id: &str) -> Self {
        Self::spawn(env!("CARGO_BIN_EXE_host-tools-mcp"), test_id)
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

struct RegisterCli {
    child: Child,
    stderr_rx: Receiver<String>,
    stderr_handle: Option<JoinHandle<()>>,
}

impl RegisterCli {
    fn spawn(binary: &str, args: &[String], test_id: &str) -> Self {
        let mut child = Command::new(binary)
            .env("TMPDIR", test_tmpdir(test_id))
            .args(args)
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .expect("failed to spawn register cli");
        let stderr = child.stderr.take().expect("missing register cli stderr");
        let (stderr_tx, stderr_rx) = mpsc::channel();
        let stderr_handle = thread::spawn(move || {
            let mut stderr = BufReader::new(stderr);
            loop {
                let mut line = String::new();
                match stderr.read_line(&mut line) {
                    Ok(0) => break,
                    Ok(_) => {
                        if stderr_tx.send(line.trim_end().to_string()).is_err() {
                            break;
                        }
                    }
                    Err(error) => panic!("failed reading register cli stderr: {error}"),
                }
            }
        });
        Self {
            child,
            stderr_rx,
            stderr_handle: Some(stderr_handle),
        }
    }

    fn exact(args: &[String], test_id: &str) -> Self {
        Self::spawn(env!("CARGO_BIN_EXE_mcp-register"), args, test_id)
    }

    fn prefix(args: &[String], test_id: &str) -> Self {
        Self::spawn(env!("CARGO_BIN_EXE_mcp-register-prefix"), args, test_id)
    }

    fn pid(&self) -> u32 {
        self.child.id()
    }

    fn recv_stderr_matching(&self, timeout: Duration, predicate: impl Fn(&str) -> bool) -> String {
        let deadline = Instant::now() + timeout;
        while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
            let line = self
                .stderr_rx
                .recv_timeout(remaining)
                .expect("timed out waiting for register cli stderr");
            if predicate(&line) {
                return line;
            }
        }
        panic!("timed out waiting for matching register cli stderr");
    }

    fn wait(&mut self) -> ExitStatus {
        let status = self.child.wait().expect("failed to wait for register cli");
        if let Some(handle) = self.stderr_handle.take() {
            let _ = handle.join();
        }
        status
    }

    fn collect_stderr(&self) -> Vec<String> {
        self.stderr_rx.try_iter().collect()
    }
}

impl Drop for RegisterCli {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        if let Some(handle) = self.stderr_handle.take() {
            let _ = handle.join();
        }
    }
}

#[test]
fn exact_cli_registers_fixed_command_and_streams_progress() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "exact-progress.sh",
        "#!/bin/sh\nset -eu\nprintf 'hello stdout\\n'\nprintf 'hello stderr\\n' >&2\n",
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_progress_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_progress_sh",
        json!({ "_meta": { "progressToken": 9 } }),
    );

    let progress_a = server.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/progress"
    });
    let progress_b = server.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/progress"
    });
    let progress_messages = vec![
        progress_a["params"]["message"].clone(),
        progress_b["params"]["message"].clone(),
    ];
    assert!(progress_messages.contains(&json!("stdout: hello stdout")));
    assert!(progress_messages.contains(&json!("stdout: hello stderr")));

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    let text = response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default();
    assert!(text.contains("hello stdout"));
    assert!(text.contains("hello stderr"));
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": 0,
            "stdout": "hello stdout\nhello stderr",
            "stderr": ""
        })
    );

    let exec_line = cli.recv_stderr_matching(DEFAULT_TIMEOUT, |line| line.starts_with("exec: "));
    assert_eq!(exec_line, format!("exec: {}", script.to_string_lossy()));
    let exit_line = cli.recv_stderr_matching(DEFAULT_TIMEOUT, |line| line.starts_with("exit: "));
    assert_eq!(exit_line, "exit: code=0");
}

#[test]
fn exact_cli_pty_renders_terminal_output() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "pty-render.sh",
        "#!/bin/sh
set -eu
printf 'stale'
printf '\r'
printf 'fresh line\n'
printf '\\033[31mred text\\033[0m\n'
printf 'stderr via tty\n' >&2
",
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["pty_render_sh"]);
    call_tool(&mut server, 2, "pty_render_sh", json!({}));

    let response = recv_or_panic_with_stderr(&server, &cli, DEFAULT_TIMEOUT, |message| {
        message["id"] == json!(2)
    });
    assert_eq!(response["result"]["isError"], json!(false));
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": 0,
            "stdout": "fresh line\nred text\nstderr via tty",
            "stderr": ""
        })
    );
    let text = response["result"]["content"][0]["text"]
        .as_str()
        .expect("content text should be a string");
    assert!(text.contains("fresh line"));
    assert!(text.contains("red text"));
    assert!(!text.contains('\u{1b}'));
}

#[test]
fn prefix_cli_forwards_args_to_command_prefix() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "echo-args.sh",
        "#!/bin/sh\nset -eu\nprintf '%s\\n' \"$*\"\n",
    );
    let _cli = RegisterCli::prefix(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["echo_args_sh"]);
    call_tool(
        &mut server,
        2,
        "echo_args_sh",
        json!({ "args": ["install", "app.apk"] }),
    );
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(
        response["result"]["content"][0]["text"],
        json!("install app.apk")
    );
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": 0,
            "stdout": "install app.apk",
            "stderr": ""
        })
    );
}

#[test]
fn prefix_cli_pty_preserves_multi_part_prefix_before_ai_args() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "echo-tty-args.sh",
        "#!/bin/sh
set -eu
printf '%s\n' \"$*\"
",
    );
    let _cli = RegisterCli::prefix(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["echo_tty_args_sh"]);
    call_tool(
        &mut server,
        2,
        "echo_tty_args_sh",
        json!({ "args": ["install", "app.apk"] }),
    );
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(
        response["result"]["content"][0]["text"],
        json!("install app.apk")
    );
}

#[test]
fn exact_cli_rejects_tool_call_arguments_without_running_command() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("exact-args-executed");
    let script = write_script(
        &test_id,
        "exact-no-args.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntouch {}\nprintf 'should not run\\n'\n",
            marker.display()
        ),
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_no_args_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_no_args_sh",
        json!({ "message": "unexpected" }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["isError"], json!(true));
    assert!(response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .contains("unknown field `message`"));
    assert!(!marker.exists(), "exact command should not have executed");

    let _ = cli;
}

#[test]
fn prefix_cli_rejects_invalid_args_and_unknown_fields() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("exec-invalid-executed");
    let script = write_script(
        &test_id,
        "exec-validate.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntouch {}\nprintf '%s\\n' \"$*\"\n",
            marker.display()
        ),
    );
    let _cli = RegisterCli::prefix(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exec_validate_sh"]);

    call_tool(
        &mut server,
        2,
        "exec_validate_sh",
        json!({ "args": "install app.apk" }),
    );
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["isError"], json!(true));
    assert!(response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .contains("Invalid args for prefix tool"));

    call_tool(
        &mut server,
        3,
        "exec_validate_sh",
        json!({ "args": ["install"], "unexpected": true }),
    );
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(3));
    assert_eq!(response["result"]["isError"], json!(true));
    assert!(response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .contains("unknown field `unexpected`"));
    assert!(!marker.exists(), "exec command should not have executed");
}

#[test]
fn prefix_cli_preserves_multi_part_prefix_before_ai_args() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "prefix-tail.sh",
        "#!/bin/sh\nset -eu\nprintf '%s\\n' \"$*\"\n",
    );
    let _cli = RegisterCli::prefix(
        &["sh".to_string(), script.to_string_lossy().to_string()],
        &test_id,
    );
    let tool_name = RegisteredCommand::argv_prefix(vec![
        "sh".to_string(),
        script.to_string_lossy().to_string(),
    ])
    .expect("valid prefix command")
    .tool_name();

    wait_for_tools(&mut server, &[tool_name.as_str()]);
    call_tool(
        &mut server,
        2,
        &tool_name,
        json!({ "args": ["alpha", "beta"] }),
    );
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(
        response["result"]["content"][0]["text"],
        json!("alpha beta")
    );
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": 0,
            "stdout": "alpha beta",
            "stderr": ""
        })
    );
}

#[test]
fn exact_cli_timeout_returns_partial_output_and_term_side_effect() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("exact-timeout-terminated");
    fs::create_dir_all(marker.parent().expect("marker should have parent"))
        .expect("failed to create marker dir");
    let script = write_script(
        &test_id,
        "exact-timeout.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntrap 'touch {}; exit 0' TERM INT\nprintf 'before timeout\\n'\nwhile true; do sleep 1; done\n",
            marker.display()
        ),
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_timeout_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_timeout_sh",
        json!({ "timeoutMs": 100 }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    wait_for_file(&marker);

    assert_eq!(response["result"]["isError"], json!(false));
    let timeout_text = response["result"]["content"]
        .as_array()
        .and_then(|content| content.first())
        .and_then(|entry| entry["text"].as_str())
        .unwrap_or_default();
    assert!(timeout_text.contains("before timeout"));
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": null,
            "stdout": timeout_text,
            "stderr": "",
            "timedOut": true,
            "timedOutMs": 100
        })
    );
}

#[test]
fn prefix_cli_timeout_returns_partial_output_and_term_side_effect() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("prefix-timeout-terminated");
    fs::create_dir_all(marker.parent().expect("marker should have parent"))
        .expect("failed to create marker dir");
    let script = write_script(
        &test_id,
        "prefix-timeout.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntrap 'touch {}; exit 0' TERM INT\nprintf 'prefix start:%s\\n' \"$1\"\nwhile true; do sleep 1; done\n",
            marker.display()
        ),
    );
    let _cli = RegisterCli::prefix(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["prefix_timeout_sh"]);
    call_tool(
        &mut server,
        2,
        "prefix_timeout_sh",
        json!({ "args": ["hello"], "timeoutMs": 100 }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    wait_for_file(&marker);

    assert_eq!(response["result"]["isError"], json!(false));
    let timeout_text = response["result"]["content"]
        .as_array()
        .and_then(|content| content.first())
        .and_then(|entry| entry["text"].as_str())
        .unwrap_or_default();
    assert!(timeout_text.contains("prefix start:hello"));
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": null,
            "stdout": timeout_text,
            "stderr": "",
            "timedOut": true,
            "timedOutMs": 100
        })
    );
}

#[test]
fn exact_cli_rejects_non_numeric_timeout() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "exact-invalid-timeout.sh",
        "#!/bin/sh\nset -eu\nprintf 'unused\\n'\n",
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_invalid_timeout_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_invalid_timeout_sh",
        json!({ "timeoutMs": "soon" }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["isError"], json!(true));
    assert!(response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .contains("Invalid args for exact tool"));
}

#[test]
fn prefix_cli_rejects_non_numeric_timeout() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "prefix-invalid-timeout.sh",
        "#!/bin/sh\nset -eu\nprintf 'unused\\n'\n",
    );
    let _cli = RegisterCli::prefix(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["prefix_invalid_timeout_sh"]);
    call_tool(
        &mut server,
        2,
        "prefix_invalid_timeout_sh",
        json!({ "args": ["hello"], "timeoutMs": "soon" }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["isError"], json!(true));
    assert!(response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .contains("Invalid args for prefix tool"));
}

#[test]
fn exact_cli_timeout_with_no_output_returns_empty_content() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("exact-timeout-no-output-terminated");
    fs::create_dir_all(marker.parent().expect("marker should have parent"))
        .expect("failed to create marker dir");
    let script = write_script(
        &test_id,
        "exact-timeout-no-output.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntrap 'touch {}; exit 0' TERM INT\nwhile true; do sleep 1; done\n",
            marker.display()
        ),
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_timeout_no_output_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_timeout_no_output_sh",
        json!({ "timeoutMs": 100 }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    wait_for_file(&marker);

    assert_eq!(response["result"]["isError"], json!(false));
    let timeout_text = response["result"]["content"]
        .as_array()
        .and_then(|content| content.first())
        .and_then(|entry| entry["text"].as_str())
        .unwrap_or_default();
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": null,
            "stdout": timeout_text,
            "stderr": "",
            "timedOut": true,
            "timedOutMs": 100
        })
    );
}

#[test]
#[ignore = "requires setpgid for SIGKILL fallback"]
fn exact_cli_timeout_force_kills_when_term_is_ignored() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "exact-timeout-force-kill.sh",
        "#!/bin/sh\nset -eu\ntrap '' TERM INT\nprintf 'ignoring term\\n'\nwhile true; do sleep 1; done\n",
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_timeout_force_kill_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_timeout_force_kill_sh",
        json!({ "timeoutMs": 100 }),
    );

    let response = server.recv_matching(EXTENDED_TIMEOUT, |message| message["id"] == json!(2));

    assert_eq!(response["result"]["isError"], json!(false));
    assert_eq!(
        response["result"]["content"][0]["text"],
        json!("ignoring term")
    );
    assert_eq!(
        response["result"]["structuredContent"]["timedOut"],
        json!(true)
    );
    assert_eq!(
        response["result"]["structuredContent"]["timedOutMs"],
        json!(100)
    );
    assert_eq!(
        response["result"]["structuredContent"]["exitCode"],
        json!(null)
    );
}

#[test]
fn exact_cli_finishing_before_timeout_does_not_report_timeout() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "exact-finishes-before-timeout.sh",
        "#!/bin/sh\nset -eu\nprintf 'done quickly\\n'\n",
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["exact_finishes_before_timeout_sh"]);
    call_tool(
        &mut server,
        2,
        "exact_finishes_before_timeout_sh",
        json!({ "timeoutMs": 1000 }),
    );

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));

    assert_eq!(response["result"]["isError"], json!(false));
    assert_eq!(
        response["result"]["content"][0]["text"],
        json!("done quickly")
    );
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": 0,
            "stdout": "done quickly",
            "stderr": ""
        })
    );
    assert_eq!(
        response["result"]["structuredContent"].get("timedOut"),
        None
    );
}

#[test]
#[ignore = "requires setpgid for descendant cleanup"]
fn exact_cli_timeout_should_kill_descendant_processes() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let child_pid_file = temp_test_dir(&test_id).join("timeout-descendant.pid");
    fs::create_dir_all(
        child_pid_file
            .parent()
            .expect("child pid file should have parent"),
    )
    .expect("failed to create child pid dir");
    let script = write_script(
        &test_id,
        "timeout-descendant.sh",
        &format!(
            "#!/bin/sh\nset -eu\nsh -c 'trap \"\" TERM INT; while true; do sleep 1; done' &\nprintf '%s\\n' \"$!\" > {}\nwhile true; do sleep 1; done\n",
            child_pid_file.display()
        ),
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["timeout_descendant_sh"]);
    call_tool(
        &mut server,
        2,
        "timeout_descendant_sh",
        json!({ "timeoutMs": 100 }),
    );

    let response = server.recv_matching(EXTENDED_TIMEOUT, |message| message["id"] == json!(2));
    wait_for_file(&child_pid_file);

    assert_eq!(
        response["result"]["structuredContent"]["timedOut"],
        json!(true)
    );

    let child_pid = fs::read_to_string(&child_pid_file)
        .expect("failed to read child pid file")
        .trim()
        .parse::<i32>()
        .expect("child pid should be an integer");
    wait_for_process_exit(child_pid);
    let alive = process_is_alive(child_pid);
    if alive {
        kill(Pid::from_raw(child_pid), Signal::SIGKILL).expect("failed to clean up child");
    }

    assert!(
        !alive,
        "descendant process {child_pid} survived timeout; process-tree termination is missing"
    );
}

#[test]
fn exact_cli_pty_timeout_should_kill_descendant_processes() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let child_pid_file = temp_test_dir(&test_id).join("pty-timeout-descendant.pid");
    fs::create_dir_all(
        child_pid_file
            .parent()
            .expect("child pid file should have parent"),
    )
    .expect("failed to create child pid dir");
    let script = write_script(
        &test_id,
        "pty-timeout-descendant.sh",
        &format!(
            "#!/bin/sh\nset -eu\nsh -c 'trap \"\" TERM INT; while true; do sleep 1; done' &\nprintf '%s\\n' \"$!\" > {}\nwhile true; do sleep 1; done\n",
            child_pid_file.display()
        ),
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["pty_timeout_descendant_sh"]);
    call_tool(
        &mut server,
        2,
        "pty_timeout_descendant_sh",
        json!({ "timeoutMs": 100 }),
    );

    let response = recv_or_panic_with_stderr(&server, &cli, EXTENDED_TIMEOUT, |message| {
        message["id"] == json!(2)
    });
    wait_for_file(&child_pid_file);
    assert_eq!(
        response["result"]["structuredContent"]["timedOut"],
        json!(true)
    );

    let child_pid = fs::read_to_string(&child_pid_file)
        .expect("failed to read child pid file")
        .trim()
        .parse::<i32>()
        .expect("child pid should be an integer");
    let alive = process_is_alive(child_pid);
    if alive {
        kill(Pid::from_raw(child_pid), Signal::SIGKILL).expect("failed to clean up child");
    }
    assert!(
        !alive,
        "descendant process {child_pid} survived PTY timeout"
    );
}

#[test]
#[ignore = "requires setpgid for descendant stdout capture"]
fn exact_cli_captures_grandchild_stdout_and_stderr_until_timeout() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let child_pid_file = temp_test_dir(&test_id).join("grandchild-output.pid");
    fs::create_dir_all(
        child_pid_file
            .parent()
            .expect("child pid file should have parent"),
    )
    .expect("failed to create child pid dir");
    let script = write_script(
        &test_id,
        "grandchild-output.sh",
        &format!(
            "#!/bin/sh\nset -eu\nsh -c 'trap \"\" TERM INT; i=1; while [ \"$i\" -le 3 ]; do printf \"grandchild stdout %s\\n\" \"$i\"; printf \"grandchild stderr %s\\n\" \"$i\" >&2; i=$((i + 1)); sleep 1; done; while true; do sleep 1; done' &\nprintf '%s\\n' \"$!\" > {}\nwhile true; do sleep 1; done\n",
            child_pid_file.display()
        ),
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["grandchild_output_sh"]);
    call_tool(
        &mut server,
        2,
        "grandchild_output_sh",
        json!({ "timeoutMs": 2500 }),
    );

    let response = server.recv_matching(EXTENDED_TIMEOUT, |message| message["id"] == json!(2));
    wait_for_file(&child_pid_file);

    assert_eq!(response["result"]["isError"], json!(false));
    assert_eq!(
        response["result"]["structuredContent"]["timedOut"],
        json!(true)
    );

    let stdout = response["result"]["structuredContent"]["stdout"]
        .as_str()
        .expect("stdout should be a string");
    let stderr = response["result"]["structuredContent"]["stderr"]
        .as_str()
        .expect("stderr should be a string");
    let text = response["result"]["content"][0]["text"]
        .as_str()
        .expect("content text should be a string");

    for line in [
        "grandchild stdout 1",
        "grandchild stdout 2",
        "grandchild stdout 3",
    ] {
        assert!(stdout.contains(line), "missing stdout line: {line}");
        assert!(text.contains(line), "missing content line: {line}");
    }
    for line in [
        "grandchild stderr 1",
        "grandchild stderr 2",
        "grandchild stderr 3",
    ] {
        assert!(stderr.contains(line), "missing stderr line: {line}");
        assert!(
            text.contains(&format!("stderr: {line}")),
            "missing content stderr line: {line}"
        );
    }

    let child_pid = fs::read_to_string(&child_pid_file)
        .expect("failed to read child pid file")
        .trim()
        .parse::<i32>()
        .expect("child pid should be an integer");
    let alive = process_is_alive(child_pid);
    if alive {
        kill(Pid::from_raw(child_pid), Signal::SIGKILL).expect("failed to clean up child");
    }
    assert!(
        !alive,
        "grandchild process {child_pid} survived timeout after producing output"
    );
}

#[test]
#[ignore = "requires setpgid for wrapper handoff"]
fn exact_cli_captures_output_from_wrapper_spawned_descendant_after_parent_exits() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let child_pid_file = temp_test_dir(&test_id).join("wrapper-descendant.pid");
    fs::create_dir_all(
        child_pid_file
            .parent()
            .expect("child pid file should have parent"),
    )
    .expect("failed to create child pid dir");
    let monitor = write_script(
        &test_id,
        "wrapper-monitor.sh",
        "#!/bin/sh\nset -eu\ntrap \"\" TERM INT\ni=1\nwhile [ \"$i\" -le 3 ]; do\n  printf 'wrapper stdout %s\\n' \"$i\"\n  printf 'wrapper stderr %s\\n' \"$i\" >&2\n  i=$((i + 1))\n  sleep 1\ndone\nwhile true; do sleep 1; done\n",
    );
    let script = write_script(
        &test_id,
        "wrapper-descendant-output.sh",
        &format!(
            "#!/bin/sh\nset -eu\nsh -c '{}' &\nprintf '%s\\n' \"$!\" > {}\n",
            monitor.display(),
            child_pid_file.display()
        ),
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["wrapper_descendant_output_sh"]);
    call_tool(
        &mut server,
        2,
        "wrapper_descendant_output_sh",
        json!({ "timeoutMs": 2500 }),
    );

    let response = server.recv_matching(EXTENDED_TIMEOUT, |message| message["id"] == json!(2));
    wait_for_file(&child_pid_file);

    assert_eq!(response["result"]["isError"], json!(false));
    assert_eq!(
        response["result"]["structuredContent"]["timedOut"],
        json!(true)
    );

    let stdout = response["result"]["structuredContent"]["stdout"]
        .as_str()
        .expect("stdout should be a string");
    let stderr = response["result"]["structuredContent"]["stderr"]
        .as_str()
        .expect("stderr should be a string");

    for line in ["wrapper stdout 1", "wrapper stdout 2", "wrapper stdout 3"] {
        assert!(stdout.contains(line), "missing stdout line: {line}");
    }
    for line in ["wrapper stderr 1", "wrapper stderr 2", "wrapper stderr 3"] {
        assert!(stderr.contains(line), "missing stderr line: {line}");
    }

    let child_pid = fs::read_to_string(&child_pid_file)
        .expect("failed to read child pid file")
        .trim()
        .parse::<i32>()
        .expect("child pid should be an integer");
    let alive = process_is_alive(child_pid);
    if alive {
        kill(Pid::from_raw(child_pid), Signal::SIGKILL).expect("failed to clean up child");
    }
    assert!(
        !alive,
        "wrapper descendant process {child_pid} survived timeout after parent exit"
    );
}

#[test]
fn exact_cli_reports_non_zero_exit_in_structured_result_and_logs_status() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "fails-with-seven.sh",
        "#!/bin/sh\nset -eu\nprintf 'before fail\\n'\nprintf 'bad news\\n' >&2\nexit 7\n",
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["fails_with_seven_sh"]);
    call_tool(&mut server, 2, "fails_with_seven_sh", json!({}));

    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["isError"], json!(true));
    assert_eq!(
        response["result"]["structuredContent"],
        json!({
            "exitCode": 7,
            "stdout": "before fail\nbad news",
            "stderr": ""
        })
    );

    let exec_line = cli.recv_stderr_matching(DEFAULT_TIMEOUT, |line| line.starts_with("exec: "));
    assert_eq!(exec_line, format!("exec: {}", script.to_string_lossy()));
    let exit_line = cli.recv_stderr_matching(DEFAULT_TIMEOUT, |line| line.starts_with("exit: "));
    assert_eq!(exit_line, "exit: code=7");
}

#[test]
fn register_cli_discovers_multiple_servers_and_survives_one_shutdown() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server_a = ChildHarness::host_tools_mcp(&test_id);
    let mut server_b = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server_a.socket_path());
    wait_for_file(&server_b.socket_path());
    initialize_client(&mut server_a);
    initialize_client(&mut server_b);

    let script = write_script(
        &test_id,
        "multi-server.sh",
        "#!/bin/sh\nset -eu\nprintf 'multi ok\\n'\n",
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server_a, &["multi_server_sh"]);
    wait_for_tools(&mut server_b, &["multi_server_sh"]);

    call_tool(&mut server_a, 2, "multi_server_sh", json!({}));
    let response = server_a.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["content"][0]["text"], json!("multi ok"));

    drop(server_a);
    wait_for_tools(&mut server_b, &["multi_server_sh"]);
    call_tool(&mut server_b, 3, "multi_server_sh", json!({}));
    let response = server_b.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(3));
    assert_eq!(response["result"]["content"][0]["text"], json!("multi ok"));
}

#[test]
#[ignore = "requires setpgid for ctrl-c cancellation"]
fn ctrl_c_in_register_cli_disconnects_and_cancels_calls() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("register-cli-cancelled");
    fs::create_dir_all(marker.parent().expect("marker should have parent"))
        .expect("failed to create marker dir");
    let script = write_script(&test_id,
        "long-running.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntrap 'touch {}; exit 0' TERM INT\nprintf 'started\\n'\nwhile true; do sleep 1; done\n",
            marker.display()
        ),
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["long_running_sh"]);
    call_tool(
        &mut server,
        2,
        "long_running_sh",
        json!({ "_meta": { "progressToken": 3 } }),
    );
    let _ = server.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/progress"
    });

    send_sigint(cli.pid());
    wait_for_file(&marker);
    let (response, list_changed) = recv_call_response_and_list_changed(&server, json!(2));
    assert!(response.get("error").is_some());
    assert_eq!(
        list_changed["method"],
        json!("notifications/tools/list_changed")
    );
}

#[test]
fn ctrl_c_in_register_cli_disconnects_and_cancels_pty_calls() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let script = write_script(
        &test_id,
        "pty-long-running.sh",
        "#!/bin/sh\nset -eu\ntrap 'exit 0' TERM INT\nprintf 'started\\n'\nwhile true; do sleep 1; done\n",
    );
    let cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["pty_long_running_sh"]);
    call_tool(
        &mut server,
        2,
        "pty_long_running_sh",
        json!({ "_meta": { "progressToken": 3 } }),
    );
    let _ = server.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/progress"
    });

    send_sigint(cli.pid());
    let (response, list_changed) = recv_call_response_and_list_changed(&server, json!(2));
    assert!(response.get("error").is_some());
    assert_eq!(
        list_changed["method"],
        json!("notifications/tools/list_changed")
    );
}

#[test]
fn server_shutdown_cancels_active_register_cli_processes() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let marker = temp_test_dir(&test_id).join("server-shutdown-cancelled");
    fs::create_dir_all(marker.parent().expect("marker should have parent"))
        .expect("failed to create marker dir");
    let script = write_script(&test_id,
        "server-shutdown.sh",
        &format!(
            "#!/bin/sh\nset -eu\ntrap 'touch {}; exit 0' TERM INT\nprintf 'started\\n'\nwhile true; do sleep 1; done\n",
            marker.display()
        ),
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["server_shutdown_sh"]);
    call_tool(
        &mut server,
        2,
        "server_shutdown_sh",
        json!({ "_meta": { "progressToken": 4 } }),
    );
    let _ = server.recv_matching(DEFAULT_TIMEOUT, |message| {
        message["method"] == "notifications/progress"
    });

    let _ = server.child.kill();
    let _ = server.child.wait();
    wait_for_file(&marker);
}

#[test]
fn register_cli_fails_cleanly_when_no_live_servers_exist() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let script = write_script(
        &test_id,
        "no-server.sh",
        "#!/bin/sh\nset -eu\nprintf 'unused\\n'\n",
    );
    let mut cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    let status = cli.wait();
    assert!(!status.success());
    let stderr = cli.collect_stderr().join("\n");
    assert!(stderr.contains("no live host-tools-mcp servers found"));
}

#[test]
fn register_cli_ignores_stale_server_dirs_and_registers_with_live_server() {
    let test_id = gen_test_id();
    let _test_dir = test_dir(&test_id);
    let mut server = ChildHarness::host_tools_mcp(&test_id);
    wait_for_file(&server.socket_path());
    initialize_client(&mut server);

    let stale_dir = test_log_root(&test_id).join("stale-server");
    fs::create_dir_all(&stale_dir).expect("failed to create stale server dir");
    fs::write(stale_dir.join("registry.sock"), b"not-a-socket")
        .expect("failed to create stale socket file");

    let script = write_script(
        &test_id,
        "stale-ok.sh",
        "#!/bin/sh\nset -eu\nprintf 'stale ok\\n'\n",
    );
    let _cli = RegisterCli::exact(&[script.to_string_lossy().to_string()], &test_id);

    wait_for_tools(&mut server, &["stale_ok_sh"]);
    call_tool(&mut server, 2, "stale_ok_sh", json!({}));
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(2));
    assert_eq!(response["result"]["content"][0]["text"], json!("stale ok"));
}

fn initialize_client(server: &mut ChildHarness) {
    server.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": 0,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {
                "name": "register-cli-test",
                "version": "0.1.0"
            }
        }
    }));
    let _ = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(0));
    server.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "method": "notifications/initialized"
    }));
}

fn wait_for_tools(server: &mut ChildHarness, expected: &[&str]) {
    let mut expected = expected
        .iter()
        .map(|name| (*name).to_string())
        .collect::<Vec<_>>();
    expected.sort();
    let deadline = Instant::now() + DEFAULT_TIMEOUT;
    let mut last_seen = Vec::new();

    while Instant::now() < deadline {
        last_seen = list_tools(server);
        if last_seen == expected {
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }

    panic!(
        "timed out waiting for expected tools: expected {:?}, got {:?}",
        expected, last_seen
    );
}

fn list_tools(server: &mut ChildHarness) -> Vec<String> {
    server.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": 99,
        "method": "tools/list"
    }));
    let response = server.recv_matching(DEFAULT_TIMEOUT, |message| message["id"] == json!(99));
    let mut names = response["result"]["tools"]
        .as_array()
        .into_iter()
        .flatten()
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

fn call_tool(server: &mut ChildHarness, id: i64, tool: &str, extra_params: Value) {
    let mut params = serde_json::Map::new();
    params.insert("name".to_string(), json!(tool));
    let mut arguments = serde_json::Map::new();
    if let Some(extra) = extra_params.as_object() {
        for (key, value) in extra {
            if key == "_meta" {
                params.insert(key.clone(), value.clone());
            } else {
                arguments.insert(key.clone(), value.clone());
            }
        }
    }
    if !arguments.is_empty() {
        params.insert("arguments".to_string(), Value::Object(arguments));
    }
    server.send_json_rpc(json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": "tools/call",
        "params": params,
    }));
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

fn recv_call_response_and_list_changed(server: &ChildHarness, id: Value) -> (Value, Value) {
    let deadline = Instant::now() + DEFAULT_TIMEOUT;
    let mut response = None;
    let mut list_changed = None;

    while Instant::now() < deadline && (response.is_none() || list_changed.is_none()) {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let message = server
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

fn recv_or_panic_with_stderr(
    server: &ChildHarness,
    cli: &RegisterCli,
    timeout: Duration,
    predicate: impl Fn(&Value) -> bool,
) -> Value {
    let deadline = Instant::now() + timeout;
    while let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
        let Some(message) = server.recv_message_timeout(remaining) else {
            panic!(
                "timed out waiting for child message; register stderr: {:?}",
                cli.collect_stderr()
            );
        };
        if predicate(&message) {
            return message;
        }
    }
    panic!(
        "timed out waiting for matching child message; register stderr: {:?}",
        cli.collect_stderr()
    );
}

fn write_script(test_id: &str, name: &str, content: &str) -> PathBuf {
    let dir = temp_test_dir(test_id);
    fs::create_dir_all(&dir).expect("failed to create temp dir");
    let path = dir.join(name);
    fs::write(&path, content).expect("failed to write script");
    let mut perms = fs::metadata(&path)
        .expect("missing script metadata")
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&path, perms).expect("failed to chmod script");
    path
}

fn temp_test_dir(test_id: &str) -> PathBuf {
    test_tmpdir(test_id).join("subdir")
}

fn send_sigint(pid: u32) {
    kill(Pid::from_raw(pid as i32), Signal::SIGINT).expect("failed to deliver SIGINT");
}

fn process_is_alive(pid: i32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

fn wait_for_process_exit(pid: i32) {
    let deadline = Instant::now() + FILE_TIMEOUT;
    while Instant::now() < deadline {
        if !process_is_alive(pid) {
            return;
        }
        thread::sleep(Duration::from_millis(10));
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
