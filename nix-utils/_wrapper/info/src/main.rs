use std::env;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::fd::RawFd;
use std::os::unix::fs::FileTypeExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

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
    dumpable_blocked: bool,
}

#[derive(Debug, Serialize)]
struct InfoOutput {
    name: String,
    configured: ConfiguredOutput,
    unix_sockets: Vec<String>,
    network_access: bool,
    real_dev: bool,
    dumpable: bool,
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

    let output = collect_info(&config, configured);
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

fn collect_info(config: &InfoConfig, configured: ConfiguredOutput) -> InfoOutput {
    let devnull_writable = is_devnull_writable();
    let (dumpable, dumpable_blocked) = probe_dumpable();
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
        dumpable_blocked,
    };
    let mut sockets = if seccomp.unix_blocked {
        Vec::new()
    } else {
        collect_unix_sockets()
    };
    sockets.sort();

    let mut protected_paths = Map::new();
    for pp in &config.protected_paths {
        let path = expand_home_path(&pp.path);
        let visible = if pp.r#type == "dir" {
            is_visible_dir(&path)
        } else {
            is_visible_file(&path)
        };
        protected_paths.insert(pp.path.clone(), Value::Bool(visible));
    }

    InfoOutput {
        name: config.program_name.clone(),
        configured,
        unix_sockets: sockets,
        network_access: detect_network_access(),
        real_dev: Path::new("/dev/input").exists(),
        dumpable,
        seccomp,
        share: ShareConfig {
            user: config.share.user,
            uts: config.share.uts,
            cgroup: config.share.cgroup,
            pid: config.share.pid,
            ipc: config.share.ipc,
        },
        protected_paths,
    }
}

fn probe_dumpable() -> (bool, bool) {
    let initial_dumpable = get_dumpable().unwrap_or(false);

    let mut dumpable_blocked = false;
    match set_dumpable(true) {
        Ok(()) => {
            if !initial_dumpable {
                let _ = set_dumpable(false);
            }
        }
        Err(err) => {
            if let Some(code) = err.raw_os_error() {
                dumpable_blocked = code == libc::EACCES || code == libc::EPERM;
            }
        }
    }

    let current_dumpable = get_dumpable().unwrap_or(initial_dumpable);
    (current_dumpable, dumpable_blocked)
}

fn get_dumpable() -> io::Result<bool> {
    let rc = unsafe { libc::prctl(libc::PR_GET_DUMPABLE, 0, 0, 0, 0) };
    if rc == -1 {
        return Err(io::Error::last_os_error());
    }

    Ok(rc != 0)
}

fn set_dumpable(is_dumpable: bool) -> io::Result<()> {
    let value = if is_dumpable { 1 } else { 0 };
    let rc = unsafe { libc::prctl(libc::PR_SET_DUMPABLE, value, 0, 0, 0) };
    if rc == -1 {
        return Err(io::Error::last_os_error());
    }

    Ok(())
}

fn collect_unix_sockets() -> Vec<String> {
    let mut out = Vec::new();

    let walker = WalkDir::new("/")
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

    out
}

fn should_skip_path(path: &Path) -> bool {
    if path == Path::new("/") {
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

fn expand_home_path(path: &str) -> String {
    if let Ok(home) = env::var("HOME") {
        if let Some(rest) = path.strip_prefix("$HOME") {
            return format!("{home}{rest}");
        }

        if let Some(rest) = path.strip_prefix("${HOME}") {
            return format!("{home}{rest}");
        }

        if let Some(rest) = path.strip_prefix("~") {
            return format!("{home}{rest}");
        }
    }

    path.to_string()
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
