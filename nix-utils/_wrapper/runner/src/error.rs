use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum RunnerError {
    #[error("usage: {0}")]
    Usage(String),

    #[error("failed to read config {path}: {source}")]
    ReadConfig {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("invalid JSON in config {path}: {source}")]
    ParseConfig {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },

    #[error("invalid config: {0}")]
    InvalidConfig(String),

    #[error("failed to spawn process '{program}': {source}")]
    SpawnProcess {
        program: String,
        #[source]
        source: std::io::Error,
    },

    #[error("failed while waiting for process '{program}': {source}")]
    WaitProcess {
        program: String,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to open file {path}: {source}")]
    OpenFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to create directory {path}: {source}")]
    CreateDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to install signal handlers: {source}")]
    SignalSetup {
        #[source]
        source: std::io::Error,
    },

    #[error("process '{program}' terminated by signal {signal}")]
    TerminatedBySignal { program: String, signal: i32 },

    #[error("failed to remove path {path}: {source}")]
    RemovePath {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("seccomp setup failed: {0}")]
    Seccomp(String),

    #[error("references ${name}, but {name} is not set")]
    UndefinedVariable { name: String },
}
