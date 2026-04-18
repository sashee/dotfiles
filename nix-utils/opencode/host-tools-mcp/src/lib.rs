use std::borrow::Cow;
use std::env;
use std::fs;
use std::io;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::Arc;

use chrono::Local;
use rmcp::model::{CallToolResult, Tool};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

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

pub fn create_server_dir() -> io::Result<PathBuf> {
    let root = log_root();
    fs::create_dir_all(&root)?;

    for attempt in 0..100u32 {
        let timestamp = Local::now().format("%Y-%m-%d_%H-%M-%S%.3f%z");
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

pub fn discover_live_servers() -> io::Result<Vec<LiveServer>> {
    let root = log_root();
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
    use super::{RegisteredCommand, MAX_TOOL_NAME_LEN};

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
