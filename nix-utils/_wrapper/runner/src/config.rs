use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::error::RunnerError;

#[derive(Debug, Deserialize)]
pub struct RunnerConfig {
    pub program_name: String,
    pub env: EnvConfig,
    pub bwrap: BwrapConfig,
    pub command: CommandConfig,
    #[serde(default)]
    pub mounts: Vec<MountRule>,
    #[serde(default)]
    pub seccomp: Option<SeccompConfig>,
    #[serde(default)]
    pub dbus: DbusConfig,
    #[serde(default)]
    pub restrict_to_git_root: bool,
}

#[derive(Debug, Deserialize)]
pub struct EnvConfig {
    #[serde(default)]
    pub clear: bool,
    #[serde(default)]
    pub passthrough: Vec<String>,
    #[serde(default)]
    pub static_values: HashMap<String, String>,
}

#[derive(Debug, Deserialize)]
pub struct BwrapConfig {
    pub bin: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub add_tmpdir_tmpfs: bool,
}

#[derive(Debug, Deserialize)]
pub struct CommandConfig {
    pub bin: String,
    #[serde(default)]
    pub args: Vec<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct MountRule {
    pub path: String,
    pub perm: String,
    #[serde(default = "default_mount_type")]
    pub r#type: String,
    #[serde(default)]
    pub source: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SeccompConfig {
    #[serde(default)]
    pub blocked_socket_families: Vec<i32>,
}

#[derive(Debug, Deserialize, Default)]
pub struct DbusConfig {
    #[serde(default)]
    pub proxy_bin: String,
    #[serde(default)]
    pub proxies: Vec<DbusProxyConfig>,
}

#[derive(Debug, Deserialize)]
pub struct DbusProxyConfig {
    pub source_bus_path: String,
    #[serde(default)]
    pub proxy_socket_path: Option<String>,
    #[serde(default)]
    pub talk: Vec<String>,
    #[serde(default)]
    pub own: Vec<String>,
    #[serde(default)]
    pub see: Vec<String>,
    #[serde(default)]
    pub call: HashMap<String, String>,
    #[serde(default)]
    pub broadcast: HashMap<String, String>,
    #[serde(default)]
    pub log: bool,
}

fn default_mount_type() -> String {
    "dir".to_string()
}

impl RunnerConfig {
    pub fn from_path(path: &Path) -> Result<Self, RunnerError> {
        let data = std::fs::read_to_string(path).map_err(|source| RunnerError::ReadConfig {
            path: path.to_path_buf(),
            source,
        })?;

        let config = serde_json::from_str::<RunnerConfig>(&data).map_err(|source| {
            RunnerError::ParseConfig {
                path: path.to_path_buf(),
                source,
            }
        })?;

        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<(), RunnerError> {
        if self.program_name.is_empty() {
            return Err(RunnerError::InvalidConfig(
                "program_name cannot be empty".to_string(),
            ));
        }

        if self.bwrap.bin.is_empty() {
            return Err(RunnerError::InvalidConfig(
                "bwrap.bin cannot be empty".to_string(),
            ));
        }

        if self.command.bin.is_empty() {
            return Err(RunnerError::InvalidConfig(
                "command.bin cannot be empty".to_string(),
            ));
        }

        for m in &self.mounts {
            if m.path.is_empty() {
                return Err(RunnerError::InvalidConfig(
                    "mounts[].path cannot be empty".to_string(),
                ));
            }

            if !(m.perm == "rw" || m.perm == "ro" || m.perm == "block") {
                return Err(RunnerError::InvalidConfig(format!(
                    "mounts[].perm must be one of rw|ro|block, got {}",
                    m.perm
                )));
            }

            if !(m.r#type == "dir" || m.r#type == "file") {
                return Err(RunnerError::InvalidConfig(format!(
                    "mounts[].type must be dir|file, got {}",
                    m.r#type
                )));
            }
        }

        let mut seen_proxy_paths: HashSet<&str> = HashSet::new();
        for proxy in &self.dbus.proxies {
            if proxy.source_bus_path.is_empty() {
                return Err(RunnerError::InvalidConfig(
                    "dbus.proxies[].source_bus_path cannot be empty".to_string(),
                ));
            }

            if let Some(proxy_socket_path) = proxy.proxy_socket_path.as_deref() {
                if proxy_socket_path.is_empty() {
                    return Err(RunnerError::InvalidConfig(
                        "dbus.proxies[].proxy_socket_path cannot be empty when set".to_string(),
                    ));
                }

                if !seen_proxy_paths.insert(proxy_socket_path) {
                    return Err(RunnerError::InvalidConfig(format!(
                        "duplicate dbus proxy socket path: {}",
                        proxy_socket_path
                    )));
                }
            }
        }

        if let Some(seccomp) = &self.seccomp {
            for family in &seccomp.blocked_socket_families {
                if *family < 0 {
                    return Err(RunnerError::InvalidConfig(format!(
                        "seccomp.blocked_socket_families[] must be >= 0, got {}",
                        family
                    )));
                }
            }
        }

        Ok(())
    }
}

pub fn resolve_config_path(path: &str) -> PathBuf {
    PathBuf::from(path)
}
