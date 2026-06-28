use std::borrow::Cow;
use std::env;
use std::fs;
use std::io;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use chrono::Local;
use rmcp::model::{CallToolResult, Tool};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

pub mod broker;
pub mod register;

pub const SOCKET_NAME: &str = "registry.sock";
const MAX_TOOL_NAME_LEN: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionMode {
    Pipe,
    Pty,
}

pub fn log_root() -> PathBuf {
    env::var("TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::temp_dir())
        .join("host-tools-mcp")
}

/// Filename of the broker's front socket — placed INSIDE [`log_root`] (alongside
/// the per-server registry dirs), not as a flat sibling: each consumer runs in a
/// bwrap sandbox whose `/tmp` is a private tmpfs with only the `host-tools-mcp/`
/// dir bind-mounted, so a flat sibling would be masked and unreachable. An
/// `ssh -R` forward maps this path; the remote must have the dir (one-time mkdir).
pub const BROKER_SOCKET_NAME: &str = "broker.sock";

/// Path the broker listens on. `mcp-register` connects here (the broker fans out
/// to the individual registries); an `ssh -R` forward maps this exact path.
pub fn broker_socket_path() -> PathBuf {
    log_root().join(BROKER_SOCKET_NAME)
}

pub fn create_server_dir() -> io::Result<PathBuf> {
    let root = log_root();
    fs::create_dir_all(&root)?;

    for attempt in 0..100u32 {
        let timestamp = Local::now().format("%Y-%m-%d_%H-%M-%S");
        let suffix = if attempt == 0 {
            String::new()
        } else {
            format!("-{attempt}")
        };
        let dir = root.join(format!("{timestamp}{suffix}"));
        match fs::create_dir(&dir) {
            Ok(()) => return Ok(dir),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }

    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "failed to allocate unique server directory",
    ))
}

pub fn debug_enabled() -> bool {
    matches!(
        env::var("MCP_REGISTER_DEBUG").as_deref(),
        Ok("1" | "true" | "yes" | "on")
    )
}

pub fn debug_log(message: impl std::fmt::Display) {
    if debug_enabled() {
        eprintln!("[mcp-register] {message}");
    }
}

#[derive(Debug, Clone)]
pub struct LiveServer {
    pub dir: PathBuf,
    pub socket_path: PathBuf,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ProviderToServer {
    RegisterTools {
        id: u64,
        tools: Vec<Tool>,
    },
    DeregisterTools {
        id: u64,
        tools: Vec<String>,
    },
    ToolCallResult {
        #[serde(rename = "callId")]
        call_id: String,
        result: CallToolResult,
    },
    ToolCallProgress {
        #[serde(rename = "callId")]
        call_id: String,
        progress: f64,
        total: Option<f64>,
        message: Option<String>,
    },
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerToProvider {
    Success {
        #[serde(rename = "inReplyTo")]
        in_reply_to: u64,
    },
    Error {
        #[serde(rename = "inReplyTo")]
        in_reply_to: u64,
        message: String,
    },
    CallTool {
        #[serde(rename = "callId")]
        call_id: String,
        tool: String,
        arguments: Map<String, Value>,
    },
    CancelCall {
        #[serde(rename = "callId")]
        call_id: String,
        reason: String,
    },
}

#[derive(Debug, Clone)]
pub enum RegisteredCommand {
    Exact {
        argv: Vec<String>,
        execution_mode: ExecutionMode,
    },
    ArgvPrefix {
        argv: Vec<String>,
        execution_mode: ExecutionMode,
    },
}

impl RegisteredCommand {
    pub fn exact(argv: Vec<String>) -> io::Result<Self> {
        Self::exact_with_mode(argv, ExecutionMode::Pty)
    }

    fn exact_with_mode(argv: Vec<String>, execution_mode: ExecutionMode) -> io::Result<Self> {
        if argv.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "missing command",
            ));
        }
        Ok(Self::Exact {
            argv,
            execution_mode,
        })
    }

    pub fn argv_prefix(argv: Vec<String>) -> io::Result<Self> {
        Self::argv_prefix_with_mode(argv, ExecutionMode::Pty)
    }

    fn argv_prefix_with_mode(argv: Vec<String>, execution_mode: ExecutionMode) -> io::Result<Self> {
        if argv.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "missing command prefix",
            ));
        }
        Ok(Self::ArgvPrefix {
            argv,
            execution_mode,
        })
    }

    pub fn execution_mode(&self) -> ExecutionMode {
        match self {
            Self::Exact { execution_mode, .. } | Self::ArgvPrefix { execution_mode, .. } => {
                *execution_mode
            }
        }
    }

    pub fn tool_name(&self) -> String {
        match self {
            Self::Exact { argv, .. } => {
                let mut parts = Vec::new();
                if let Some((first, rest)) = argv.split_first() {
                    parts.push(basename(first).to_string());
                    parts.extend(rest.iter().cloned());
                }
                sanitize_tool_name(&parts)
            }
            Self::ArgvPrefix { argv, .. } => {
                let mut parts = Vec::new();
                if let Some((first, rest)) = argv.split_first() {
                    parts.push(basename(first).to_string());
                    parts.extend(rest.iter().cloned());
                }
                sanitize_tool_name(&parts)
            }
        }
    }

    pub fn description(&self) -> String {
        match self {
            Self::Exact {
                argv,
                execution_mode,
            } => format!(
                "Runs the fixed command `{}`{} Takes no command arguments and optionally accepts `timeoutMs`.",
                argv.join(" "),
                execution_mode_description(*execution_mode)
            ),
            Self::ArgvPrefix {
                argv,
                execution_mode,
            } => format!(
                "Runs the fixed command prefix `{}`{} Accepts trailing arguments as a string array and optionally accepts `timeoutMs`.",
                argv.join(" "),
                execution_mode_description(*execution_mode)
            ),
        }
    }

    pub fn tool_definition(&self) -> Tool {
        let schema = match self {
            Self::Exact { .. } => json!({
                "type": "object",
                "properties": {
                    "timeoutMs": {
                        "type": "integer",
                        "minimum": 1
                    }
                },
                "additionalProperties": false
            }),
            Self::ArgvPrefix { .. } => json!({
                "type": "object",
                "properties": {
                    "args": {
                        "type": "array",
                        "items": { "type": "string" }
                    },
                    "timeoutMs": {
                        "type": "integer",
                        "minimum": 1
                    }
                },
                "additionalProperties": false
            }),
        };

        let mut tool = Tool::default();
        tool.name = Cow::Owned(self.tool_name());
        tool.description = Some(Cow::Owned(self.description()));
        tool.input_schema = Arc::new(
            serde_json::from_value(schema).expect("tool schema should be a valid JSON object"),
        );
        tool
    }
}

/// Scan `log_root()` for live registry servers. Used by the **broker** to find
/// and fan out to the registries (`mcp-register` itself only talks to the broker).
pub fn discover_live_servers() -> io::Result<Vec<LiveServer>> {
    discover_in(&log_root())
}

fn discover_in(root: &Path) -> io::Result<Vec<LiveServer>> {
    if !root.exists() {
        debug_log(format!("discovery root {} does not exist", root.display()));
        return Ok(Vec::new());
    }

    debug_log(format!("scanning {} for live servers", root.display()));
    let mut servers = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let dir = entry.path();
        if !dir.is_dir() {
            debug_log(format!("skipping {}: not a directory", dir.display()));
            continue;
        }

        debug_log(format!("checking {}", dir.display()));

        let socket_path = dir.join(SOCKET_NAME);
        if !socket_path.exists() {
            debug_log(format!(
                "skipping {}: missing {}",
                dir.display(),
                socket_path.display()
            ));
            continue;
        }

        match UnixStream::connect(&socket_path) {
            Ok(stream) => {
                let _ = stream.shutdown(std::net::Shutdown::Both);
            }
            Err(error) => {
                debug_log(format!(
                    "skipping {}: failed to connect to {}: {error}",
                    dir.display(),
                    socket_path.display()
                ));
                continue;
            }
        }

        debug_log(format!(
            "accepted {} with socket {}",
            dir.display(),
            socket_path.display()
        ));
        servers.push(LiveServer { dir, socket_path });
    }

    servers.sort_by(|left, right| left.dir.cmp(&right.dir));
    debug_log(format!("discovered {} live server(s)", servers.len()));
    Ok(servers)
}

/// The broker at [`broker_socket_path`], if it is live. `mcp-register` connects
/// only here — the broker fans out to the individual registries. `None` when no
/// broker is listening (then `mcp-register` errors).
pub fn live_broker_server() -> Option<LiveServer> {
    broker_at(broker_socket_path())
}

/// `Some(server)` if `socket_path` is a connectable socket; `None` if it's
/// missing or not connectable (e.g. a stale regular file). Split out from
/// [`live_broker_server`] so it can be unit-tested with an arbitrary path.
fn broker_at(socket_path: PathBuf) -> Option<LiveServer> {
    if !socket_path.exists() {
        return None;
    }
    match UnixStream::connect(&socket_path) {
        Ok(stream) => {
            let _ = stream.shutdown(std::net::Shutdown::Both);
            let dir = socket_path
                .parent()
                .map(PathBuf::from)
                .unwrap_or_else(|| socket_path.clone());
            Some(LiveServer { dir, socket_path })
        }
        Err(error) => {
            debug_log(format!(
                "broker socket {} not connectable: {error}",
                socket_path.display()
            ));
            None
        }
    }
}

fn sanitize_tool_name(parts: &[String]) -> String {
    let mut name = parts
        .iter()
        .flat_map(|part| part.chars())
        .map(|ch| {
            if ch.is_ascii_alphanumeric() {
                ch.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect::<String>();
    while name.contains("__") {
        name = name.replace("__", "_");
    }
    let trimmed = name.trim_matches('_');
    let capped = trimmed.chars().take(MAX_TOOL_NAME_LEN).collect::<String>();
    capped.trim_matches('_').to_string()
}

fn execution_mode_description(execution_mode: ExecutionMode) -> &'static str {
    match execution_mode {
        ExecutionMode::Pipe => ".",
        ExecutionMode::Pty => " in a terminal-emulated PTY with rendered plain-text output. Stdout and stderr are combined.",
    }
}

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

#[derive(Debug, Clone)]
pub struct ProgressUpdate {
    pub progress: f64,
    pub total: Option<f64>,
    pub message: Option<String>,
}

pub fn progress_message(line_index: usize, stream: &str, line: &str) -> ProgressUpdate {
    ProgressUpdate {
        progress: line_index as f64,
        total: None,
        message: Some(format!("{stream}: {line}")),
    }
}

#[cfg(test)]
mod tests {
    use super::{broker_at, discover_in, RegisteredCommand, MAX_TOOL_NAME_LEN, SOCKET_NAME};
    use std::os::unix::net::UnixListener;

    #[test]
    fn broker_at_requires_a_live_socket() {
        let base = std::env::temp_dir().join(format!("htm-broker-at-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(&base).unwrap();

        // missing -> None
        assert!(broker_at(base.join("absent.sock")).is_none());

        // stale regular file -> None
        let stale = base.join("stale.sock");
        std::fs::write(&stale, b"not-a-socket").unwrap();
        assert!(broker_at(stale).is_none());

        // live listener -> Some
        let live = base.join("live.sock");
        let _listener = UnixListener::bind(&live).unwrap();
        let server = broker_at(live.clone()).expect("live socket should be Some");
        assert_eq!(server.socket_path, live);
        assert_eq!(server.dir, base);

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn discover_in_skips_non_sockets_and_returns_live_servers() {
        let base = std::env::temp_dir().join(format!("htm-discover-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(&base).unwrap();

        // live: a real listening socket
        let live = base.join("live");
        std::fs::create_dir_all(&live).unwrap();
        let _listener = UnixListener::bind(live.join(SOCKET_NAME)).unwrap();

        // stale: a regular file where the socket should be (not connectable)
        let stale = base.join("stale");
        std::fs::create_dir_all(&stale).unwrap();
        std::fs::write(stale.join(SOCKET_NAME), b"not-a-socket").unwrap();

        // a top-level file (not a directory) must be ignored
        std::fs::write(base.join("loose.sock"), b"x").unwrap();

        let found = discover_in(&base).unwrap();
        assert_eq!(found.len(), 1, "only the live server is returned: {found:?}");
        assert_eq!(found[0].socket_path, live.join(SOCKET_NAME));

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn tool_name_is_capped() {
        let command = RegisteredCommand::exact(vec![
            "/tmp/this-is-a-very-long-command-name-that-keeps-going-and-going-and-going".into(),
            "with-even-more-arguments".into(),
            "and-even-more-arguments".into(),
        ])
        .expect("command should parse");

        let tool_name = command.tool_name();
        assert!(tool_name.len() <= MAX_TOOL_NAME_LEN);
        assert_eq!(
            tool_name,
            "this_is_a_very_long_command_name_that_keeps_going_and_going_and"
        );
    }
}
