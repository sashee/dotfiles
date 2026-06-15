use std::collections::HashSet;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::fd::RawFd;
use std::os::unix::fs::FileTypeExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Deserialize;
use serde::Serialize;
use serde_json::{Map, Value};
use thiserror::Error;
use walkdir::WalkDir;

const EXCLUDED_SOCKET_ROOTS: &[&str] = &["nix", "proc", "sys", "usr", "lib", "snap"];

#[derive(Debug, Error)]
enum InfoError {
    #[error("usage: {0}")]
    Usage(String),

    #[error("failed to read config {path}: {source}")]
    ReadConfig { path: PathBuf, source: io::Error },

    #[error("invalid JSON in config {path}: {source}")]
    ParseConfig {
        path: PathBuf,
        source: serde_json::Error,
    },

    #[error("failed to read {label} JSON {path}: {source}")]
    ReadJson {
        label: &'static str,
        path: PathBuf,
        source: io::Error,
    },

    #[error("invalid JSON in {label} {path}: {source}")]
    ParseJson {
        label: &'static str,
        path: PathBuf,
        source: serde_json::Error,
    },

    #[error("failed to serialize output: {0}")]
    Serialize(serde_json::Error),

    #[error("unsupported path expansion in protected path {path}: {var}")]
    UnsupportedPathExpansion { path: String, var: String },

    #[error("protected path {path} references ${var}, but {var} is not set")]
    MissingPathEnv { path: String, var: String },
}

#[derive(Debug, Deserialize)]
struct Cli {
    config_path: String,
    launcher_args_path: Option<String>,
    sandbox_restrictions_path: Option<String>,
    runner_config_path: Option<String>,
}

#[derive(Debug, Deserialize)]
struct InfoConfig {
    program_name: String,
    share: ShareConfig,
    protected_paths: Vec<ProtectedPathConfig>,
    #[serde(default)]
    optional_env_vars: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct ShareConfig {
    user: bool,
    uts: bool,
    cgroup: bool,
    pid: bool,
    ipc: bool,
}

#[derive(Debug, Deserialize)]
struct ProtectedPathConfig {
    path: String,
    r#type: String,
}

#[derive(Debug, Serialize)]
struct SeccompOutput {
    inet_blocked: bool,
    inet6_blocked: bool,
    unix_blocked: bool,
    netlink_blocked: bool,
    packet_blocked: bool,
    bluetooth_blocked: bool,
}

#[derive(Debug, Serialize)]
struct InfoOutput {
    name: String,
    configured: ConfiguredOutput,
    dev: Vec<String>,
    unix_sockets: Vec<String>,
    network_access: bool,
    real_dev: bool,
    seccomp: SeccompOutput,
    share: ShareConfig,
    protected_paths: Map<String, Value>,
}

#[derive(Debug, Serialize)]
struct ConfiguredOutput {
    launcher_args: Value,
    sandbox_restrictions: Value,
    runner_config: Value,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), InfoError> {
    let cli = parse_cli(env::args_os().collect())?;
    let config_path = PathBuf::from(&cli.config_path);
    let config = read_config(&config_path)?;
    let configured = ConfiguredOutput {
        launcher_args: read_optional_json(cli.launcher_args_path.as_deref(), "launcher args")?,
        sandbox_restrictions: read_optional_json(
            cli.sandbox_restrictions_path.as_deref(),
            "sandbox restrictions",
        )?,
        runner_config: read_optional_json(cli.runner_config_path.as_deref(), "runner config")?,
    };

    let output = collect_info(&config, configured)?;
    let json = serde_json::to_string_pretty(&output).map_err(InfoError::Serialize)?;
    println!("{json}");

    Ok(())
}

fn parse_cli(args: Vec<OsString>) -> Result<Cli, InfoError> {
    let usage = "nix-sandbox-info --config <path> [--launcher-args <path>] [--sandbox-restrictions <path>] [--runner-config <path>]".to_string();

    if args.len() < 3 || args.len() % 2 == 0 {
        return Err(InfoError::Usage(usage));
    }

    let mut config_path: Option<String> = None;
    let mut launcher_args_path: Option<String> = None;
    let mut sandbox_restrictions_path: Option<String> = None;
    let mut runner_config_path: Option<String> = None;

    let mut i = 1;
    while i + 1 < args.len() {
        let flag = args[i]
            .to_str()
            .ok_or_else(|| InfoError::Usage("flag must be valid UTF-8".to_string()))?;
        let value = args[i + 1]
            .to_str()
            .ok_or_else(|| InfoError::Usage("path must be valid UTF-8".to_string()))?
            .to_string();

        match flag {
            "--config" => config_path = Some(value),
            "--launcher-args" => launcher_args_path = Some(value),
            "--sandbox-restrictions" => sandbox_restrictions_path = Some(value),
            "--runner-config" => runner_config_path = Some(value),
            _ => return Err(InfoError::Usage(usage)),
        }

        i += 2;
    }

    Ok(Cli {
        config_path: config_path.ok_or_else(|| InfoError::Usage(usage.clone()))?,
        launcher_args_path,
        sandbox_restrictions_path,
        runner_config_path,
    })
}

fn read_config(path: &Path) -> Result<InfoConfig, InfoError> {
    let data = fs::read_to_string(path).map_err(|source| InfoError::ReadConfig {
        path: path.to_path_buf(),
        source,
    })?;

    serde_json::from_str::<InfoConfig>(&data).map_err(|source| InfoError::ParseConfig {
        path: path.to_path_buf(),
        source,
    })
}

fn read_optional_json(path: Option<&str>, label: &'static str) -> Result<Value, InfoError> {
    let Some(path) = path else {
        return Ok(Value::Null);
    };

    let path_buf = PathBuf::from(path);
    let data = fs::read_to_string(&path_buf).map_err(|source| InfoError::ReadJson {
        label,
        path: path_buf.clone(),
        source,
    })?;

    serde_json::from_str::<Value>(&data).map_err(|source| InfoError::ParseJson {
        label,
        path: path_buf,
        source,
    })
}

fn collect_info(
    config: &InfoConfig,
    configured: ConfiguredOutput,
) -> Result<InfoOutput, InfoError> {
    let devnull_writable = is_devnull_writable();
    let seccomp = SeccompOutput {
        inet_blocked: socket_blocked(devnull_writable, libc::AF_INET, libc::SOCK_STREAM, 0),
        inet6_blocked: socket_blocked(devnull_writable, libc::AF_INET6, libc::SOCK_STREAM, 0),
        unix_blocked: socket_blocked(devnull_writable, libc::AF_UNIX, libc::SOCK_STREAM, 0),
        netlink_blocked: socket_blocked(devnull_writable, libc::AF_NETLINK, libc::SOCK_DGRAM, 0),
        packet_blocked: socket_blocked(devnull_writable, libc::AF_PACKET, libc::SOCK_RAW, 0),
        bluetooth_blocked: socket_blocked(
            devnull_writable,
            libc::AF_BLUETOOTH,
            libc::SOCK_STREAM,
            0,
        ),
    };
    let mut sockets = if seccomp.unix_blocked {
        Vec::new()
    } else {
        collect_unix_sockets()
    };
    sockets.sort();
    let fake_dev_baseline = fake_dev_entry_names(&configured.runner_config);
    let mut dev = collect_visible_dev_entries(&fake_dev_baseline);
    dev.sort();

    let mut protected_paths = Map::new();
    for pp in &config.protected_paths {
        if references_missing_optional_env_var(&pp.path, &config.optional_env_vars, |name| {
            env::var(name).ok()
        }) {
            protected_paths.insert(pp.path.clone(), Value::Bool(false));
            continue;
        }

        let path = expand_path(&pp.path)?;
        let visible = if pp.r#type == "dir" {
            is_visible_dir(&path)
        } else {
            is_visible_file(&path)
        };
        protected_paths.insert(pp.path.clone(), Value::Bool(visible));
    }

    Ok(InfoOutput {
        name: config.program_name.clone(),
        configured,
        dev,
        unix_sockets: sockets,
        network_access: detect_network_access(),
        real_dev: Path::new("/dev/input").exists(),
        seccomp,
        share: ShareConfig {
            user: config.share.user,
            uts: config.share.uts,
            cgroup: config.share.cgroup,
            pid: config.share.pid,
            ipc: config.share.ipc,
        },
        protected_paths,
    })
}

fn collect_visible_dev_entries(fake_dev_baseline: &HashSet<String>) -> Vec<String> {
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir("/dev") else {
        return out;
    };

    for entry in entries {
        let Ok(entry) = entry else {
            continue;
        };
        let path = entry.path();
        let Some(path_str) = path.to_str() else {
            continue;
        };
        let Some(file_name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if fake_dev_baseline.contains(&file_name) {
            continue;
        }
        if !is_accessible_dev_entry(&path) {
            continue;
        }
        out.push(path_str.to_string());
    }

    out
}

fn fake_dev_entry_names(runner_config: &Value) -> HashSet<String> {
    let Some(bwrap_bin) = runner_config
        .get("bwrap")
        .and_then(|v| v.get("bin"))
        .and_then(Value::as_str)
    else {
        return HashSet::new();
    };

    let Some(command_bin) = runner_config
        .get("command")
        .and_then(|v| v.get("bin"))
        .and_then(Value::as_str)
    else {
        return HashSet::new();
    };

    let output = match Command::new(bwrap_bin)
        .args(["--ro-bind", "/", "/", "--dev", "/dev", command_bin])
        .args([
            "--noprofile",
            "--norc",
            "-c",
            "for p in /dev/*; do printf '%s\n' \"${p##*/}\"; done",
        ])
        .output()
    {
        Ok(output) if output.status.success() => output,
        _ => return HashSet::new(),
    };

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn is_accessible_dev_entry(path: &Path) -> bool {
    let symlink_meta = match fs::symlink_metadata(path) {
        Ok(meta) => meta,
        Err(_) => return false,
    };

    let file_type = symlink_meta.file_type();
    if file_type.is_symlink() {
        return fs::metadata(path).is_ok();
    }

    if file_type.is_dir() {
        return fs::read_dir(path)
            .map(|mut entries| entries.next().is_some())
            .unwrap_or(false);
    }

    is_visible_file(&path.to_string_lossy())
}

fn collect_unix_sockets() -> Vec<String> {
    let mut out = Vec::new();

    for root in socket_scan_roots() {
        let walker = WalkDir::new(root)
            .follow_links(false)
            .into_iter()
            .filter_entry(|e| !should_skip_path(e.path()));

        for entry in walker {
            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => continue,
            };

            if entry.file_type().is_socket() {
                out.push(to_relative_path(entry.path()));
            }
        }
    }

    out.sort();
    out.dedup();
    out
}

fn socket_scan_roots() -> Vec<String> {
    let mut roots = vec![
        "/run".to_string(),
        "/var/run".to_string(),
        "/tmp".to_string(),
    ];

    if let Ok(runtime_dir) = env::var("XDG_RUNTIME_DIR") {
        roots.push(runtime_dir);
    }

    roots
        .into_iter()
        .filter(|path| {
            fs::metadata(path)
                .map(|meta| meta.is_dir())
                .unwrap_or(false)
        })
        .collect()
}

fn should_skip_path(path: &Path) -> bool {
    if path == Path::new("/")
        || path == Path::new("/run")
        || path == Path::new("/var/run")
        || path == Path::new("/tmp")
    {
        return false;
    }

    let mut components = path.components();
    if components.next().is_none() {
        return false;
    }

    match components.next() {
        Some(c) => EXCLUDED_SOCKET_ROOTS.contains(&c.as_os_str().to_str().unwrap_or_default()),
        None => false,
    }
}

fn to_relative_path(path: &Path) -> String {
    path.strip_prefix("/")
        .unwrap_or(path)
        .to_string_lossy()
        .to_string()
}

fn detect_network_access() -> bool {
    let content = match fs::read_to_string("/proc/net/dev") {
        Ok(content) => content,
        Err(_) => return false,
    };

    for line in content.lines().skip(2) {
        let iface = match line.split_once(':') {
            Some((name, _)) => name.trim(),
            None => continue,
        };

        if !iface.is_empty() && iface != "lo" {
            return true;
        }
    }

    false
}

fn socket_blocked(devnull_writable: bool, family: i32, ty: i32, proto: i32) -> bool {
    if !devnull_writable {
        return true;
    }

    let fd: RawFd = unsafe { libc::socket(family, ty, proto) };
    if fd < 0 {
        true
    } else {
        unsafe {
            libc::close(fd);
        }
        false
    }
}

fn is_devnull_writable() -> bool {
    std::fs::OpenOptions::new()
        .write(true)
        .open("/dev/null")
        .is_ok()
}

fn expand_path(path: &str) -> Result<String, InfoError> {
    expand_path_with_env(path, |name| env::var(name).ok())
}

fn expand_path_with_env<F>(path: &str, env_lookup: F) -> Result<String, InfoError>
where
    F: Fn(&str) -> Option<String>,
{
    if let Some(rest) = path.strip_prefix('~') {
        let home = lookup_supported_path_var(path, "HOME", &env_lookup)?;
        return expand_path_with_env(&format!("{home}{rest}"), env_lookup);
    }

    let mut out = String::new();
    let chars: Vec<char> = path.chars().collect();
    let mut i = 0usize;

    while i < chars.len() {
        if chars[i] != '$' {
            out.push(chars[i]);
            i += 1;
            continue;
        }

        if i + 1 >= chars.len() {
            out.push('$');
            i += 1;
            continue;
        }

        if chars[i + 1] == '{' {
            let mut j = i + 2;
            while j < chars.len() && chars[j] != '}' {
                j += 1;
            }
            if j >= chars.len() {
                out.push('$');
                i += 1;
                continue;
            }

            let name: String = chars[(i + 2)..j].iter().collect();
            out.push_str(&lookup_supported_path_var(path, &name, &env_lookup)?);
            i = j + 1;
            continue;
        }

        let mut j = i + 1;
        while j < chars.len() && (chars[j].is_ascii_alphanumeric() || chars[j] == '_') {
            j += 1;
        }

        if j == i + 1 {
            out.push('$');
            i += 1;
            continue;
        }

        let name: String = chars[(i + 1)..j].iter().collect();
        out.push_str(&lookup_supported_path_var(path, &name, &env_lookup)?);
        i = j;
    }

    Ok(out)
}

fn lookup_supported_path_var<F>(path: &str, name: &str, env_lookup: &F) -> Result<String, InfoError>
where
    F: Fn(&str) -> Option<String>,
{
    if !matches!(name, "HOME" | "XDG_RUNTIME_DIR" | "WAYLAND_DISPLAY") {
        return Err(InfoError::UnsupportedPathExpansion {
            path: path.to_string(),
            var: name.to_string(),
        });
    }

    let Some(value) = env_lookup(name) else {
        return Err(InfoError::MissingPathEnv {
            path: path.to_string(),
            var: name.to_string(),
        });
    };

    Ok(value)
}

fn references_env_var(input: &str, name: &str) -> bool {
    [format!("${name}"), format!("${{{name}}}")]
        .iter()
        .any(|needle| input.contains(needle))
}

fn references_missing_optional_env_var<F>(
    path: &str,
    optional_env_vars: &[String],
    env_lookup: F,
) -> bool
where
    F: Fn(&str) -> Option<String>,
{
    optional_env_vars
        .iter()
        .any(|name| references_env_var(path, name) && env_lookup(name).is_none())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup(name: &str) -> Option<String> {
        match name {
            "HOME" => Some("/home/test".to_string()),
            "XDG_RUNTIME_DIR" => Some("/run/user/123".to_string()),
            "WAYLAND_DISPLAY" => Some("wayland-0".to_string()),
            _ => None,
        }
    }

    #[test]
    fn expands_xdg_runtime_dir_prefix() {
        assert_eq!(
            expand_path_with_env("$XDG_RUNTIME_DIR/bus", lookup).unwrap(),
            "/run/user/123/bus"
        );
    }

    #[test]
    fn expands_braced_xdg_runtime_dir_prefix() {
        assert_eq!(
            expand_path_with_env("${XDG_RUNTIME_DIR}/bus", lookup).unwrap(),
            "/run/user/123/bus"
        );
    }

    #[test]
    fn expands_wayland_display_path() {
        assert_eq!(
            expand_path_with_env("$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY", lookup).unwrap(),
            "/run/user/123/wayland-0"
        );
        assert_eq!(
            expand_path_with_env("${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}", lookup).unwrap(),
            "/run/user/123/wayland-0"
        );
    }

    #[test]
    fn expands_home_prefixes() {
        assert_eq!(
            expand_path_with_env("$HOME/.config", lookup).unwrap(),
            "/home/test/.config"
        );
        assert_eq!(
            expand_path_with_env("${HOME}/.config", lookup).unwrap(),
            "/home/test/.config"
        );
        assert_eq!(
            expand_path_with_env("~/.config", lookup).unwrap(),
            "/home/test/.config"
        );
    }

    #[test]
    fn leaves_absolute_paths_unchanged() {
        assert_eq!(
            expand_path_with_env("/run/docker.sock", lookup).unwrap(),
            "/run/docker.sock"
        );
    }

    #[test]
    fn errors_for_unsupported_env_expansion() {
        let err = expand_path_with_env("$FOO/bar", lookup).unwrap_err();
        assert!(matches!(
            err,
            InfoError::UnsupportedPathExpansion { ref var, .. } if var == "FOO"
        ));
    }

    #[test]
    fn errors_for_missing_supported_env_expansion() {
        let err = expand_path_with_env("$XDG_RUNTIME_DIR/bus", |_| None).unwrap_err();
        assert!(matches!(
            err,
            InfoError::MissingPathEnv { ref var, .. } if var == "XDG_RUNTIME_DIR"
        ));
    }

    fn optional_env_vars() -> Vec<String> {
        vec!["WAYLAND_DISPLAY".to_string(), "SSH_AUTH_SOCK".to_string()]
    }

    #[test]
    fn detects_missing_optional_wayland_display_path() {
        assert!(references_missing_optional_env_var(
            "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY",
            &optional_env_vars(),
            |name| match name {
                "XDG_RUNTIME_DIR" => Some("/run/user/123".to_string()),
                _ => None,
            }
        ));
    }

    #[test]
    fn detects_missing_optional_ssh_auth_sock_path() {
        assert!(references_missing_optional_env_var(
            "$SSH_AUTH_SOCK",
            &optional_env_vars(),
            |_| None
        ));
    }

    #[test]
    fn var_not_in_optional_list_is_not_optional() {
        assert!(!references_missing_optional_env_var(
            "$SSH_AUTH_SOCK",
            &[],
            |_| None
        ));
    }
}

fn is_visible_dir(path: &str) -> bool {
    let meta = match fs::metadata(path) {
        Ok(meta) => meta,
        Err(_) => return false,
    };

    if !meta.is_dir() {
        return false;
    }

    match fs::read_dir(path) {
        Ok(mut rd) => rd.next().is_some(),
        Err(_) => false,
    }
}

fn is_visible_file(path: &str) -> bool {
    let path_meta = match fs::metadata(path) {
        Ok(meta) => meta,
        Err(_) => return false,
    };

    let devnull_meta = match fs::metadata("/dev/null") {
        Ok(meta) => meta,
        Err(_) => return true,
    };

    if path_meta.dev() == devnull_meta.dev() && path_meta.ino() == devnull_meta.ino() {
        return false;
    }

    true
}
