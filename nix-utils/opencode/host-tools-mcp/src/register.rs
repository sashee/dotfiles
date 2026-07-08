use std::collections::HashMap;
use std::fs::File;
use std::io;
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::os::unix::process::ExitStatusExt;
use std::process::Command as StdCommand;
use std::process::Stdio;
use std::thread;

use anyhow::{anyhow, bail, Context, Result};
use nix::fcntl::{fcntl, FcntlArg, FdFlag};
use nix::pty::openpty;
use nix::sys::signal::{kill, signal, SigHandler, Signal};
use nix::sys::wait::{waitpid, WaitStatus};
use nix::unistd::setpgid;
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
    broker_socket_path, debug_log, live_broker_server, progress_message, ExecutionMode,
    LiveServer, ProgressUpdate, ProviderToServer, RegisteredCommand, ServerToProvider,
};

/// Upper bound on how long a finished PTY command's output may keep flowing
/// before the result is returned without waiting for EOF. Only reached when an
/// orphaned grandchild keeps the PTY slave open past the child's exit; in the
/// normal case EOF arrives immediately and the result returns right away.
const PTY_EOF_FALLBACK: Duration = Duration::from_millis(2000);

pub async fn run_register(mode: RegisteredCommand) -> Result<()> {
    debug_log(format!(
        "starting registration for tool {}",
        mode.tool_name()
    ));
    // mcp-register only ever talks to the broker (the broker fans out to every
    // registry). Locally that's the auto-started broker; over an ssh -R forward
    // it's the remote-side broker socket — same known path either way.
    let servers = match live_broker_server() {
        Some(broker) => {
            debug_log(format!(
                "registering via broker at {}",
                broker.socket_path.display()
            ));
            vec![broker]
        }
        None => bail!(
            "no broker at {} — is a host-tools-mcp client running, or the socket forwarded?",
            broker_socket_path().display()
        ),
    };

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

struct ParsedCommand {
    program: String,
    args: Vec<String>,
    timeout_ms: Option<u64>,
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
    let ParsedCommand {
        program,
        args,
        timeout_ms,
    } = match parse_command(mode, arguments) {
        Ok(command) => command,
        Err(result) => return Ok(Some(result)),
    };

    eprintln!("exec: {}", format_command_for_log(&program, &args));

    let output = match mode.execution_mode() {
        ExecutionMode::Pipe => {
            run_piped_command(&program, &args, timeout_ms, call_id, cancel_rx, events_tx).await?
        }
        ExecutionMode::Pty => {
            run_pty_command(&program, &args, timeout_ms, call_id, cancel_rx, events_tx).await?
        }
    };

    if let Some(code) = output.status.code() {
        eprintln!("exit: code={code}");
    } else if let Some(signal) = output.status.signal() {
        eprintln!("exit: signal={signal}");
    } else {
        eprintln!("exit: unknown");
    }

    Ok(Some(build_result(
        output.status,
        output.stdout,
        output.stderr,
        output.timed_out,
        timeout_ms,
    )))
}

struct CommandOutput {
    status: std::process::ExitStatus,
    stdout: String,
    stderr: String,
    timed_out: bool,
}

async fn run_piped_command(
    program: &str,
    args: &[String],
    timeout_ms: Option<u64>,
    call_id: &str,
    cancel_rx: &mut oneshot::Receiver<()>,
    events_tx: &mpsc::UnboundedSender<RunnerEvent>,
) -> Result<CommandOutput> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // `pre_exec` is unsafe by std contract (the closure runs in the forked child);
    // the body uses only async-signal-safe calls. Irreducible.
    #[allow(unsafe_code)]
    unsafe {
        command.pre_exec(|| {
            setpgid(Pid::from_raw(0), Pid::from_raw(0)).map_err(io::Error::other)?;
            signal(Signal::SIGTTOU, SigHandler::SigIgn).map_err(io::Error::other)?;
            signal(Signal::SIGTTIN, SigHandler::SigIgn).map_err(io::Error::other)?;
            signal(Signal::SIGTSTP, SigHandler::SigIgn).map_err(io::Error::other)?;
            Ok(())
        });
    }
    let mut child = command
        .spawn()
        .with_context(|| format!("failed to spawn {program}"))?;
    let process_group_id = child.id().context("missing child pid")? as i32;

    let stdout = child.stdout.take().context("missing child stdout")?;
    let stderr = child.stderr.take().context("missing child stderr")?;
    let (output_tx, mut output_rx) = mpsc::unbounded_channel::<OutputEvent>();

    let _stdout_handle = tokio::spawn(read_output_stream(
        stdout,
        OutputKind::Stdout,
        output_tx.clone(),
    ));
    let _stderr_handle = tokio::spawn(read_output_stream(stderr, OutputKind::Stderr, output_tx));

    let execution = collect_command_output(
        &mut child,
        process_group_id,
        timeout_ms,
        call_id,
        cancel_rx,
        events_tx,
        &mut output_rx,
    )
    .await?;

    Ok(execution)
}

async fn run_pty_command(
    program: &str,
    args: &[String],
    timeout_ms: Option<u64>,
    call_id: &str,
    cancel_rx: &mut oneshot::Receiver<()>,
    events_tx: &mpsc::UnboundedSender<RunnerEvent>,
) -> Result<CommandOutput> {
    let pty = openpty(None, None).context("failed to allocate PTY")?;
    // Keep the PTY fds out of unrelated concurrently spawned children: a leaked
    // slave fd would hold EOF back until that child exits. The intended child
    // still receives the slave via dup2, which clears CLOEXEC on its stdio.
    for fd in [&pty.master, &pty.slave] {
        fcntl(fd, FcntlArg::F_SETFD(FdFlag::FD_CLOEXEC))
            .context("failed to set CLOEXEC on PTY fd")?;
    }
    let master = File::from(pty.master);
    let slave = File::from(pty.slave);
    let slave_stdout = slave.try_clone().context("failed to clone PTY slave")?;
    let slave_stdin = slave.try_clone().context("failed to clone PTY slave")?;

    let mut command = StdCommand::new(program);
    command
        .args(args)
        .stdin(Stdio::from(slave_stdin))
        .stdout(Stdio::from(slave_stdout))
        .stderr(Stdio::from(slave));
    // `pre_exec` is unsafe by std contract (the closure runs in the forked child);
    // the body uses only async-signal-safe calls. Irreducible.
    #[allow(unsafe_code)]
    unsafe {
        command.pre_exec(|| {
            setpgid(Pid::from_raw(0), Pid::from_raw(0)).map_err(io::Error::other)?;
            Ok(())
        });
    }
    let child = command
        .spawn()
        .with_context(|| format!("failed to spawn {program}"))?;
    let process_group_id = child.id() as i32;
    let child_pid = Pid::from_raw(process_group_id);
    // Close the parent's copies of the PTY slave (held by `command`'s Stdio
    // handles): the master only reports EOF once every slave fd is closed, and
    // EOF is what tells us the output has been fully drained.
    drop(command);
    let (status_tx, mut status_rx) =
        mpsc::unbounded_channel::<io::Result<std::process::ExitStatus>>();
    let (output_tx, mut output_rx) = mpsc::unbounded_channel::<OutputEvent>();

    let wait_handle = thread::spawn(move || {
        let _ = status_tx.send(wait_for_pid(child_pid));
    });
    let _output_handle = thread::spawn(move || read_pty_stream(master, output_tx));
    let mut stdout_lines = Vec::new();
    let mut latest_stdout = String::new();
    let mut next_progress = 1usize;
    let mut exit_status = None;
    let mut output_closed = false;
    let mut timed_out = false;
    let timeout_sleep =
        timeout_ms.map(|ms| Box::pin(tokio::time::sleep(Duration::from_millis(ms))));
    let mut timeout_sleep = timeout_sleep;
    // Armed when the child exits. EOF normally follows right after (the parent
    // holds no slave fds), so this only fires when something else — an orphaned
    // grandchild — still holds the PTY slave open after the child exited.
    let mut eof_fallback = None;

    while !(output_closed && exit_status.is_some()) {
        tokio::select! {
            maybe_status = status_rx.recv(), if exit_status.is_none() => {
                let status = maybe_status
                    .ok_or_else(|| anyhow!("PTY child wait channel closed unexpectedly"))?
                    .context("failed to wait for PTY child")?;
                exit_status = Some(status);
                eof_fallback = Some(Box::pin(tokio::time::sleep(PTY_EOF_FALLBACK)));
            }
            maybe_output = output_rx.recv(), if !output_closed => {
                match maybe_output {
                    Some(OutputEvent::Line { kind: OutputKind::Stdout, line }) => {
                        println!("{line}");
                        stdout_lines.push(line.clone());
                        let _ = events_tx.send(RunnerEvent::Progress {
                            call_id: call_id.to_string(),
                            update: progress_message(next_progress, "stdout", &line),
                        });
                        next_progress += 1;
                    }
                    Some(OutputEvent::Snapshot { kind: OutputKind::Stdout, text }) => {
                        latest_stdout = text;
                    }
                    Some(OutputEvent::Line { kind: OutputKind::Stderr, .. }) => {}
                    Some(OutputEvent::Snapshot { kind: OutputKind::Stderr, .. }) => {}
                    Some(OutputEvent::Closed) | None => {
                        output_closed = true;
                    }
                }
            }
            _ = async {
                if let Some(sleep) = eof_fallback.as_mut() {
                    sleep.await;
                }
            }, if eof_fallback.is_some() => {
                break;
            }
            _ = &mut *cancel_rx => {
                let _ = terminate_process_group_and_wait(process_group_id, &mut status_rx).await;
                eprintln!("exit: cancelled");
                let _ = wait_handle.join();
                return Err(anyhow!("tool call was cancelled"));
            }
            _ = async {
                if let Some(sleep) = timeout_sleep.as_mut() {
                    sleep.await;
                }
            }, if timeout_sleep.is_some() => {
                timed_out = true;
                exit_status = Some(terminate_process_group_and_wait(process_group_id, &mut status_rx).await?);
                timeout_sleep = None;
                eof_fallback = Some(Box::pin(tokio::time::sleep(PTY_EOF_FALLBACK)));
            }
        }
    }

    let _ = wait_handle.join();
    Ok(CommandOutput {
        status: exit_status.context("PTY child exited without status")?,
        stdout: if latest_stdout.is_empty() {
            stdout_lines.join("\n")
        } else {
            latest_stdout
        },
        stderr: String::new(),
        timed_out,
    })
}

async fn terminate_process_group_and_wait(
    process_group_id: i32,
    status_rx: &mut mpsc::UnboundedReceiver<io::Result<std::process::ExitStatus>>,
) -> Result<std::process::ExitStatus> {
    let _ = kill_process_group(process_group_id, Signal::SIGTERM);
    let term_status =
        if let Ok(Some(status)) = timeout(Duration::from_millis(1500), status_rx.recv()).await {
            Some(status.context("failed to wait for PTY child after SIGTERM")?)
        } else {
            None
        };

    let _ = kill_process_group(process_group_id, Signal::SIGKILL);
    if let Some(status) = term_status {
        return Ok(status);
    }

    let status = timeout(Duration::from_millis(1500), status_rx.recv())
        .await
        .context("timed out waiting for PTY child after SIGKILL")?
        .ok_or_else(|| anyhow!("PTY child wait channel closed unexpectedly"))?;
    status.context("failed to wait for PTY child after SIGKILL")
}

fn wait_for_pid(pid: Pid) -> io::Result<std::process::ExitStatus> {
    loop {
        match waitpid(pid, None).map_err(io::Error::other)? {
            WaitStatus::Exited(_, code) => {
                return Ok(std::process::ExitStatus::from_raw(code << 8));
            }
            WaitStatus::Signaled(_, signal, core_dumped) => {
                let raw = (signal as i32) | if core_dumped { 0x80 } else { 0 };
                return Ok(std::process::ExitStatus::from_raw(raw));
            }
            WaitStatus::Stopped(_, _)
            | WaitStatus::Continued(_)
            | WaitStatus::PtraceEvent(_, _, _)
            | WaitStatus::PtraceSyscall(_) => continue,
            WaitStatus::StillAlive => continue,
        }
    }
}

async fn collect_command_output(
    child: &mut tokio::process::Child,
    process_group_id: i32,
    timeout_ms: Option<u64>,
    call_id: &str,
    cancel_rx: &mut oneshot::Receiver<()>,
    events_tx: &mpsc::UnboundedSender<RunnerEvent>,
    output_rx: &mut mpsc::UnboundedReceiver<OutputEvent>,
) -> Result<CommandOutput> {
    let mut stdout_lines = Vec::new();
    let mut stderr_lines = Vec::new();
    let mut next_progress = 1usize;
    let mut exit_status = None;
    let mut timed_out = false;
    let timeout_sleep =
        timeout_ms.map(|ms| Box::pin(tokio::time::sleep(Duration::from_millis(ms))));
    let mut timeout_sleep = timeout_sleep;

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
                    Some(OutputEvent::Snapshot { .. }) => {}
                    Some(OutputEvent::Closed) => {
                        if exit_status.is_some() {
                            break;
                        }
                    }
                    None => {
                        if exit_status.is_some() {
                            break;
                        }
                    }
                }
            }
            _ = &mut *cancel_rx => {
                terminate_child(child, process_group_id).await;
                eprintln!("exit: cancelled");
                return Err(anyhow!("tool call was cancelled"));
            }
            _ = async {
                if let Some(sleep) = timeout_sleep.as_mut() {
                    sleep.await;
                }
            }, if timeout_sleep.is_some() => {
                timed_out = true;
                terminate_child(child, process_group_id).await;
                exit_status = Some(child.wait().await.context("failed to wait for timed out child")?);
                timeout_sleep = None;
            }
        }
    }

    Ok(CommandOutput {
        status: exit_status.context("child exited without status")?,
        stdout: stdout_lines.join("\n"),
        stderr: stderr_lines.join("\n"),
        timed_out,
    })
}

fn parse_command(
    mode: &RegisteredCommand,
    arguments: &Map<String, Value>,
) -> std::result::Result<ParsedCommand, CallToolResult> {
    match mode {
        RegisteredCommand::Exact { argv, .. } => {
            #[derive(Deserialize)]
            #[serde(deny_unknown_fields)]
            struct ExactArgs {
                #[serde(rename = "timeoutMs")]
                timeout_ms: Option<u64>,
            }

            let parsed = serde_json::from_value::<ExactArgs>(Value::Object(arguments.clone()))
                .map_err(|error| {
                    CallToolResult::error(vec![Content::text(format!(
                        "Invalid args for exact tool: {error}"
                    ))])
                })?;
            Ok(ParsedCommand {
                program: argv[0].clone(),
                args: argv[1..].to_vec(),
                timeout_ms: parsed.timeout_ms,
            })
        }
        RegisteredCommand::ArgvPrefix { argv: prefix, .. } => {
            #[derive(Deserialize)]
            #[serde(deny_unknown_fields)]
            struct PrefixArgs {
                #[serde(default)]
                args: Vec<String>,
                #[serde(rename = "timeoutMs")]
                timeout_ms: Option<u64>,
            }

            let parsed = serde_json::from_value::<PrefixArgs>(Value::Object(arguments.clone()))
                .map_err(|error| {
                    CallToolResult::error(vec![Content::text(format!(
                        "Invalid args for prefix tool: {error}"
                    ))])
                })?;
            let (program, fixed_args) = prefix
                .split_first()
                .expect("argv prefix should contain at least one element");
            let args = fixed_args
                .iter()
                .cloned()
                .chain(parsed.args)
                .collect::<Vec<_>>();
            Ok(ParsedCommand {
                program: program.clone(),
                args,
                timeout_ms: parsed.timeout_ms,
            })
        }
    }
}

fn build_result(
    status: std::process::ExitStatus,
    stdout: String,
    stderr: String,
    timed_out: bool,
    timeout_ms: Option<u64>,
) -> CallToolResult {
    let mut structured = Map::new();
    structured.insert(
        "exitCode".to_string(),
        if timed_out {
            Value::Null
        } else {
            status.code().map_or(Value::Null, |code| Value::from(code))
        },
    );
    if let Some(signal) = status.signal() {
        structured.insert("signal".to_string(), Value::from(signal));
    }
    if timed_out {
        structured.insert("timedOut".to_string(), Value::Bool(true));
        if let Some(timeout_ms) = timeout_ms {
            structured.insert("timedOutMs".to_string(), Value::from(timeout_ms));
        }
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

    let mut result = if timed_out || status.success() {
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
    Snapshot { kind: OutputKind, text: String },
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
                    line: line.trim_end_matches(['\r', '\n']).to_string(),
                });
            }
            Err(_) => {
                let _ = output_tx.send(OutputEvent::Closed);
                break;
            }
        }
    }
}

fn read_pty_stream(mut master: File, output_tx: mpsc::UnboundedSender<OutputEvent>) {
    let mut renderer = PtyRenderer::new();
    let mut buffer = [0u8; 4096];
    loop {
        match master.read(&mut buffer) {
            Ok(0) => {
                let (lines, snapshot) = renderer.finish();
                for line in lines {
                    let _ = output_tx.send(OutputEvent::Line {
                        kind: OutputKind::Stdout,
                        line,
                    });
                }
                let _ = output_tx.send(OutputEvent::Snapshot {
                    kind: OutputKind::Stdout,
                    text: snapshot,
                });
                let _ = output_tx.send(OutputEvent::Closed);
                break;
            }
            Ok(read) => {
                let (lines, snapshot) = renderer.feed(&buffer[..read]);
                for line in lines {
                    let _ = output_tx.send(OutputEvent::Line {
                        kind: OutputKind::Stdout,
                        line,
                    });
                }
                let _ = output_tx.send(OutputEvent::Snapshot {
                    kind: OutputKind::Stdout,
                    text: snapshot,
                });
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => {
                let _ = output_tx.send(OutputEvent::Closed);
                break;
            }
        }
    }
}

struct PtyRenderer {
    parser: vt100::Parser,
    last_lines: Vec<String>,
}

impl PtyRenderer {
    fn new() -> Self {
        Self {
            parser: vt100::Parser::new(200, 200, 5000),
            last_lines: Vec::new(),
        }
    }

    fn feed(&mut self, bytes: &[u8]) -> (Vec<String>, String) {
        self.parser.process(bytes);
        let next_lines = rendered_screen_lines(self.parser.screen());
        let changed = diff_rendered_lines(&self.last_lines, &next_lines);
        let snapshot = next_lines.join("\n");
        self.last_lines = next_lines;
        (changed, snapshot)
    }

    fn finish(&mut self) -> (Vec<String>, String) {
        let next_lines = rendered_screen_lines(self.parser.screen());
        let changed = diff_rendered_lines(&self.last_lines, &next_lines);
        let snapshot = next_lines.join("\n");
        self.last_lines = next_lines;
        (changed, snapshot)
    }
}

fn rendered_screen_lines(screen: &vt100::Screen) -> Vec<String> {
    let (rows, cols) = screen.size();
    let mut lines = screen
        .rows(0, cols)
        .take(rows as usize)
        .map(|line| line.trim_end().to_string())
        .collect::<Vec<_>>();
    while lines.last().is_some_and(|line| line.is_empty()) {
        lines.pop();
    }
    lines
}

fn diff_rendered_lines(previous: &[String], next: &[String]) -> Vec<String> {
    let mut changed = Vec::new();
    let max_len = previous.len().max(next.len());
    for index in 0..max_len {
        let before = previous.get(index);
        let after = next.get(index);
        if before != after {
            if let Some(after) = after {
                if !after.is_empty() {
                    changed.push(after.clone());
                }
            }
        }
    }
    changed
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

async fn terminate_child(child: &mut tokio::process::Child, process_group_id: i32) {
    let _ = kill(Pid::from_raw(process_group_id), Signal::SIGTERM);
    let _ = timeout(Duration::from_millis(1500), child.wait()).await;

    let _ = kill_process_group(process_group_id, Signal::SIGKILL);
    if timeout(Duration::from_millis(1500), child.wait())
        .await
        .is_ok()
    {
        return;
    }

    let _ = child.kill().await;
    let _ = child.wait().await;
}

fn kill_process_group(process_group_id: i32, signal: Signal) -> nix::Result<()> {
    kill(Pid::from_raw(-process_group_id), signal)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    async fn run_pty_script(script: &str) -> CommandOutput {
        let (_cancel_tx, mut cancel_rx) = oneshot::channel();
        let (events_tx, _events_rx) = mpsc::unbounded_channel();
        run_pty_command(
            "sh",
            &["-c".to_string(), script.to_string()],
            None,
            "test-call",
            &mut cancel_rx,
            &events_tx,
        )
        .await
        .expect("pty command should run")
    }

    // Regression for the mcp-bridge CI flake: output that reaches the PTY reader
    // only after the child's exit status was processed must not be dropped. The
    // backgrounded subshell outlives `sh` and writes 300ms after it exits — far
    // beyond the old fixed 50ms drain window.
    #[tokio::test]
    async fn pty_output_arriving_after_child_exit_is_captured() {
        let output = run_pty_script("(sleep 0.3; echo late-line) &").await;
        assert!(output.status.success());
        assert!(
            output.stdout.contains("late-line"),
            "output written after the child exited must be captured, got {:?}",
            output.stdout
        );
    }

    // The read loop must end via PTY EOF (all slave fds closed), not by burning
    // the whole fallback: if the parent's slave fds leak again, EOF never comes
    // and this takes PTY_EOF_FALLBACK.
    #[tokio::test]
    async fn pty_read_ends_via_eof_without_fallback_delay() {
        let started = Instant::now();
        let output = run_pty_script("echo hi").await;
        assert!(output.stdout.contains("hi"));
        assert!(
            started.elapsed() < PTY_EOF_FALLBACK,
            "a plain command must finish via EOF, not the fallback timer (took {:?})",
            started.elapsed()
        );
    }

    // A grandchild that keeps the PTY slave open must not stall the result
    // forever: the fallback returns the output collected so far.
    #[tokio::test]
    async fn pty_fallback_bounds_a_held_open_pty() {
        let started = Instant::now();
        let output = run_pty_script("echo hi; sleep 10 &").await;
        let elapsed = started.elapsed();
        assert!(output.status.success());
        assert!(output.stdout.contains("hi"));
        assert!(
            elapsed >= PTY_EOF_FALLBACK,
            "EOF cannot arrive while the grandchild holds the PTY (took {elapsed:?})"
        );
        assert!(
            elapsed < Duration::from_secs(8),
            "the fallback must bound the wait (took {elapsed:?})"
        );
    }
}
