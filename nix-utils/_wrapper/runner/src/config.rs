use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::error::RunnerError;

#[derive(Debug, Deserialize)]
pub struct RunnerConfig {
    pub program_name: String,
    pub bwrap: BwrapConfig,
    pub command: CommandConfig,
    #[serde(default)]
    pub debug_bwrap: bool,
    #[serde(default)]
    pub dev: DevConfig,
    /// The /dev nodes `bwrap --dev` creates, supplied from consts.nix. Used to
    /// keep those nodes when block-mounting non-allowlisted real devices, instead
    /// of probing bwrap on every launch.
    #[serde(default)]
    pub fake_dev_entries: Vec<String>,
    #[serde(default)]
    pub mounts: Vec<MountRule>,
    #[serde(default)]
    pub seccomp: Option<SeccompConfig>,
    #[serde(default)]
    pub dbus: DbusConfig,
    #[serde(default)]
    pub restrict_to_git_root: bool,
    #[serde(default)]
    pub quiet: bool,
    #[serde(default)]
    pub real_machine_id: bool,
    #[serde(default)]
    pub optional_env_vars: Vec<String>,
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

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(untagged)]
pub enum DevConfig {
    #[default]
    Disabled,
    Enabled(bool),
    Allowlist(Vec<String>),
}

#[derive(Debug, Deserialize, Clone)]
pub struct MountRule {
    pub path: String,
    pub perm: String,
    #[serde(default = "default_mount_type")]
    pub r#type: String,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub mkdir: bool,
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

        match &self.dev {
            DevConfig::Disabled => {}
            DevConfig::Enabled(enabled) => {
                let _ = *enabled;
            }
            DevConfig::Allowlist(patterns) => {
                for pattern in patterns {
                    if !pattern.starts_with("/dev/") {
                        return Err(RunnerError::InvalidConfig(format!(
                            "dev allowlist entries must start with /dev/, got {pattern}",
                        )));
                    }
                }
                // Fail closed: without the bwrap-created baseline we'd block
                // essential nodes (e.g. /dev/null) when applying the allowlist.
                if self.fake_dev_entries.is_empty() {
                    return Err(RunnerError::InvalidConfig(
                        "fake_dev_entries must be non-empty when dev is an allowlist".to_string(),
                    ));
                }
            }
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

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(json: &str) -> RunnerConfig {
        serde_json::from_str(json).expect("test json should deserialize")
    }

    const VALID: &str = r#"{
        "program_name": "t",
        "bwrap": { "bin": "/bin/bwrap" },
        "command": { "bin": "/bin/sh" }
    }"#;

    fn is_invalid(c: &RunnerConfig) -> bool {
        matches!(c.validate(), Err(RunnerError::InvalidConfig(_)))
    }

    #[test]
    fn accepts_minimal_valid_config() {
        assert!(parse(VALID).validate().is_ok());
    }

    #[test]
    fn rejects_empty_program_name() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"","bwrap":{"bin":"/b"},"command":{"bin":"/s"}}"#
        )));
    }

    #[test]
    fn rejects_empty_bwrap_bin() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":""},"command":{"bin":"/s"}}"#
        )));
    }

    #[test]
    fn rejects_empty_command_bin() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":""}}"#
        )));
    }

    #[test]
    fn rejects_bad_mount_perm() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "mounts":[{"path":"/x","perm":"bogus"}]}"#
        )));
    }

    #[test]
    fn rejects_bad_mount_type() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "mounts":[{"path":"/x","perm":"rw","type":"weird"}]}"#
        )));
    }

    #[test]
    fn rejects_empty_mount_path() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "mounts":[{"path":"","perm":"rw"}]}"#
        )));
    }

    #[test]
    fn rejects_dev_pattern_without_dev_prefix() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "dev":["/foo"]}"#
        )));
    }

    #[test]
    fn accepts_dev_pattern_with_dev_prefix() {
        assert!(parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "dev":["/dev/ttyUSB*"],"fake_dev_entries":["null","zero"]}"#
        )
        .validate()
        .is_ok());
    }

    #[test]
    fn rejects_dev_allowlist_without_fake_dev_entries() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "dev":["/dev/ttyUSB*"]}"#
        )));
    }

    #[test]
    fn rejects_duplicate_dbus_socket() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "dbus":{"proxies":[
                 {"source_bus_path":"/a","proxy_socket_path":"/tmp/p.sock"},
                 {"source_bus_path":"/b","proxy_socket_path":"/tmp/p.sock"}
               ]}}"#
        )));
    }

    #[test]
    fn rejects_negative_seccomp_family() {
        assert!(is_invalid(&parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "seccomp":{"blocked_socket_families":[-1]}}"#
        )));
    }

    #[test]
    fn quiet_and_real_machine_id_default_false() {
        let c = parse(VALID);
        assert!(!c.quiet);
        assert!(!c.real_machine_id);
    }

    #[test]
    fn parses_quiet_and_real_machine_id_true() {
        let c = parse(
            r#"{"program_name":"t","bwrap":{"bin":"/b"},"command":{"bin":"/s"},
               "quiet":true,"real_machine_id":true}"#,
        );
        assert!(c.quiet);
        assert!(c.real_machine_id);
    }
}
