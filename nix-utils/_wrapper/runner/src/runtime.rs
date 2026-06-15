use std::collections::HashMap;
use std::ffi::CString;
use std::ffi::OsString;
use std::fs;
use std::fs::OpenOptions;
use std::io::{Seek, SeekFrom};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::process::CommandExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::thread::JoinHandle;
use std::time::Duration;

use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use nix::unistd::{Gid, Uid};
use signal_hook::consts::signal::{SIGHUP, SIGINT, SIGQUIT, SIGTERM};
use signal_hook::iterator::{Handle as SignalHandle, Signals};

use glob::Pattern;

use crate::config::{DbusProxyConfig, DevConfig, MountRule, RunnerConfig};
use crate::error::RunnerError;

static NEXT_PROXY_ID: AtomicU64 = AtomicU64::new(0);
const SECCOMP_FD: i32 = 3;
const DEBUG_LOG_DIR: &str = "/tmp/nix-utils-debug";

struct ProxyHandle {
    socket_path: String,
    source_bus_path: String,
    child: Child,
}

struct ProxyGuard {
    proxies: Vec<ProxyHandle>,
}

struct SignalForwarder {
    handle: SignalHandle,
    thread: Option<JoinHandle<()>>,
}

impl ProxyGuard {
    fn from_vec(proxies: Vec<ProxyHandle>) -> Self {
        Self { proxies }
    }

    fn iter(&self) -> std::slice::Iter<'_, ProxyHandle> {
        self.proxies.iter()
    }
}

impl Drop for ProxyGuard {
    fn drop(&mut self) {
        for proxy in &mut self.proxies {
            let _ = proxy.cleanup();
        }
    }
}

impl Drop for SignalForwarder {
    fn drop(&mut self) {
        self.handle.close();
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

impl ProxyHandle {
    fn cleanup(&mut self) -> Result<(), RunnerError> {
        let _ = self.child.kill();
        let _ = self.child.wait();

        match fs::remove_file(&self.socket_path) {
            Ok(_) => Ok(()),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(source) => Err(RunnerError::RemovePath {
                path: self.socket_path.clone().into(),
                source,
            }),
        }
    }
}

pub fn run(config: RunnerConfig, passthrough_args: Vec<OsString>) -> Result<i32, RunnerError> {
    let host_env = host_env_map();
    let blocked_socket_families = config
        .seccomp
        .as_ref()
        .map(|s| s.blocked_socket_families.clone())
        .unwrap_or_default();
    let use_seccomp = !blocked_socket_families.is_empty();

    let mut proxies = Vec::new();
    for proxy in &config.dbus.proxies {
        proxies.push(start_dbus_proxy(
            proxy,
            &config.dbus.proxy_bin,
            &config.program_name,
            &host_env,
        )?);
    }
    let proxies = ProxyGuard::from_vec(proxies);

    let proxy_pids = Arc::new(Mutex::new(
        proxies
            .iter()
            .map(|p| p.child.id() as i32)
            .collect::<Vec<i32>>(),
    ));

    let mut bwrap_args: Vec<String> = config
        .bwrap
        .args
        .iter()
        .map(|arg| expand_value(arg, &host_env))
        .collect::<Result<Vec<_>, _>>()?;

    for arg in &mut bwrap_args {
        *arg = replace_runtime_tokens(arg);
    }

    if config.bwrap.add_tmpdir_tmpfs {
        let tmpdir = host_env.get("TMPDIR").map(|s| s.as_str()).unwrap_or("");
        if !tmpdir.is_empty() && tmpdir != "/tmp" {
            bwrap_args.push("--tmpfs".to_string());
            bwrap_args.push(tmpdir.to_string());
        }
    }

    if config.restrict_to_git_root {
        let restrict_path = find_git_root_or_cwd();
        eprintln!(
            "[{}] Restricting to folder: {}",
            config.program_name, restrict_path
        );
        bwrap_args.push("--bind".to_string());
        bwrap_args.push(restrict_path.clone());
        bwrap_args.push(restrict_path);
    }

    let mut mounts = config.mounts.clone();
    mounts.extend(dev_allowlist_block_mounts(&config)?);

    ensure_mount_dirs(&mounts, &host_env, &config.optional_env_vars)?;

    append_mount_args(&mut bwrap_args, &mounts, &host_env, &config.optional_env_vars)?;

    for proxy in proxies.iter() {
        bwrap_args.push("--bind".to_string());
        bwrap_args.push(proxy.socket_path.clone());
        bwrap_args.push(proxy.source_bus_path.clone());
    }

    if use_seccomp {
        bwrap_args.push("--seccomp".to_string());
        bwrap_args.push(SECCOMP_FD.to_string());
    }

    let command_bin = expand_value(&config.command.bin, &host_env)?;
    let command_args = config
        .command
        .args
        .iter()
        .map(|arg| expand_value(arg, &host_env))
        .collect::<Result<Vec<_>, _>>()?;

    let mut cmd = Command::new(&config.bwrap.bin);
    cmd.args(&bwrap_args);
    cmd.arg(command_bin);
    cmd.args(command_args);
    cmd.args(passthrough_args);

    if config.debug_bwrap {
        let rendered = std::iter::once(config.bwrap.bin.as_str())
            .chain(bwrap_args.iter().map(String::as_str))
            .chain(std::iter::once(config.command.bin.as_str()))
            .chain(config.command.args.iter().map(String::as_str))
            .map(shell_escape)
            .collect::<Vec<_>>()
            .join(" ");
        eprintln!("[{}] bwrap argv: {}", config.program_name, rendered);
    }

    let seccomp_file = if use_seccomp {
        let seccomp_file = build_seccomp_filter_fd(&blocked_socket_families)?;
        let target_fd = SECCOMP_FD;
        let source_fd = seccomp_file.as_raw_fd();
        unsafe {
            cmd.pre_exec(move || {
                let rc = nix::libc::dup2(source_fd, target_fd);
                if rc == -1 {
                    Err(std::io::Error::last_os_error())
                } else {
                    let flags = nix::libc::fcntl(target_fd, nix::libc::F_GETFD);
                    if flags == -1 {
                        return Err(std::io::Error::last_os_error());
                    }

                    let clear_rc = nix::libc::fcntl(
                        target_fd,
                        nix::libc::F_SETFD,
                        flags & !nix::libc::FD_CLOEXEC,
                    );
                    if clear_rc == -1 {
                        return Err(std::io::Error::last_os_error());
                    }

                    Ok(())
                }
            });
        }

        Some(seccomp_file)
    } else {
        None
    };

    let signal_thread = install_signal_forwarders(proxy_pids.clone())?;

    let mut child = cmd.spawn().map_err(|source| RunnerError::SpawnProcess {
        program: config.bwrap.bin.clone(),
        source,
    })?;

    if let Ok(mut pids) = proxy_pids.lock() {
        pids.push(child.id() as i32);
    }

    drop(seccomp_file);

    let status = child.wait().map_err(|source| RunnerError::WaitProcess {
        program: config.bwrap.bin.clone(),
        source,
    })?;

    drop(signal_thread);

    if let Some(code) = status.code() {
        Ok(code)
    } else if let Some(signal) = status.signal() {
        Err(RunnerError::TerminatedBySignal {
            program: config.command.bin,
            signal,
        })
    } else {
        Ok(1)
    }
}

fn build_seccomp_filter_fd(blocked_socket_families: &[i32]) -> Result<fs::File, RunnerError> {
    let action_errno_eacces = libseccomp_sys::SCMP_ACT_ERRNO(nix::libc::EACCES as u16);
    let mut filter_file = create_seccomp_memfd()?;

    let ctx = unsafe { libseccomp_sys::seccomp_init(libseccomp_sys::SCMP_ACT_ALLOW) };
    if ctx.is_null() {
        return Err(RunnerError::Seccomp("seccomp_init failed".to_string()));
    }

    let result = (|| {
        for family in blocked_socket_families {
            let cmp = libseccomp_sys::scmp_arg_cmp {
                arg: 0,
                op: libseccomp_sys::scmp_compare::SCMP_CMP_EQ,
                datum_a: *family as u64,
                datum_b: 0,
            };

            let rc = unsafe {
                libseccomp_sys::seccomp_rule_add_array(
                    ctx,
                    action_errno_eacces,
                    nix::libc::SYS_socket as i32,
                    1,
                    &cmp,
                )
            };

            if rc < 0 {
                return Err(RunnerError::Seccomp(format!(
                    "failed to add seccomp rule for socket family {family}: errno {}",
                    -rc
                )));
            }
        }

        let export_rc = unsafe { libseccomp_sys::seccomp_export_bpf(ctx, filter_file.as_raw_fd()) };
        if export_rc < 0 {
            return Err(RunnerError::Seccomp(format!(
                "seccomp_export_bpf failed: errno {}",
                -export_rc
            )));
        }

        filter_file.seek(SeekFrom::Start(0)).map_err(|source| {
            RunnerError::Seccomp(format!("failed to rewind seccomp filter file: {source}"))
        })?;

        Ok(())
    })();

    unsafe {
        libseccomp_sys::seccomp_release(ctx);
    }

    result.map(|_| filter_file)
}

fn dev_allowlist_block_mounts(config: &RunnerConfig) -> Result<Vec<MountRule>, RunnerError> {
    let patterns = match &config.dev {
        DevConfig::Allowlist(patterns) => patterns,
        _ => return Ok(Vec::new()),
    };

    let compiled_patterns = patterns
        .iter()
        .map(|pattern| {
            Pattern::new(pattern).map_err(|err| {
                RunnerError::InvalidConfig(format!(
                    "invalid dev allowlist pattern {pattern}: {err}"
                ))
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let fake_dev_entries = fake_dev_entry_names(config)?;
    let mut block_mounts = Vec::new();
    let read_dir = fs::read_dir("/dev").map_err(|source| RunnerError::OpenFile {
        path: "/dev".into(),
        source,
    })?;

    for entry in read_dir {
        let entry = entry.map_err(|source| RunnerError::OpenFile {
            path: "/dev".into(),
            source,
        })?;
        let file_name = entry.file_name();
        let Some(file_name) = file_name.to_str() else {
            continue;
        };

        if fake_dev_entries.contains(file_name) {
            continue;
        }

        let path = format!("/dev/{file_name}");
        if compiled_patterns
            .iter()
            .any(|pattern| pattern.matches(&path))
        {
            continue;
        }

        let file_type = entry.file_type().map_err(|source| RunnerError::OpenFile {
            path: path.clone().into(),
            source,
        })?;

        if file_type.is_symlink() {
            continue;
        }

        let mount_type = if file_type.is_dir() { "dir" } else { "file" };

        block_mounts.push(MountRule {
            path,
            perm: "block".to_string(),
            r#type: mount_type.to_string(),
            source: None,
            mkdir: false,
        });
    }

    Ok(block_mounts)
}

fn fake_dev_entry_names(
    config: &RunnerConfig,
) -> Result<std::collections::HashSet<String>, RunnerError> {
    let output = Command::new(&config.bwrap.bin)
        .args(["--ro-bind", "/", "/", "--dev", "/dev", &config.command.bin])
        .args([
            "--noprofile",
            "--norc",
            "-c",
            "for p in /dev/*; do printf '%s\n' \"${p##*/}\"; done",
        ])
        .output()
        .map_err(|source| RunnerError::SpawnProcess {
            program: config.bwrap.bin.clone(),
            source,
        })?;

    if !output.status.success() {
        return Err(RunnerError::InvalidConfig(format!(
            "failed to probe fake /dev baseline: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }

    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect())
}

fn create_seccomp_memfd() -> Result<fs::File, RunnerError> {
    let name = CString::new("nix-sandbox-seccomp")
        .map_err(|source| RunnerError::Seccomp(format!("invalid memfd name: {source}")))?;
    let fd = unsafe { nix::libc::memfd_create(name.as_ptr(), nix::libc::MFD_CLOEXEC) };
    if fd < 0 {
        return Err(RunnerError::Seccomp(format!(
            "memfd_create failed: {}",
            std::io::Error::last_os_error()
        )));
    }

    let file = unsafe { fs::File::from_raw_fd(fd) };
    Ok(file)
}

fn start_dbus_proxy(
    cfg: &DbusProxyConfig,
    proxy_bin: &str,
    program_name: &str,
    host_env: &HashMap<String, String>,
) -> Result<ProxyHandle, RunnerError> {
    let mut proxy_cmd = Command::new(if proxy_bin.is_empty() {
        "xdg-dbus-proxy"
    } else {
        proxy_bin
    });

    let source_bus_path = expand_path_value(&cfg.source_bus_path, host_env)?;
    let socket_path = cfg
        .proxy_socket_path
        .as_deref()
        .map(|path| expand_path_value(path, host_env))
        .transpose()?
        .unwrap_or_else(default_proxy_socket_path);

    proxy_cmd.arg(format!("unix:path={source_bus_path}"));
    proxy_cmd.arg(&socket_path);
    proxy_cmd.arg("--filter");
    proxy_cmd.stdin(Stdio::null());

    if cfg.log {
        proxy_cmd.arg("--log");

        fs::create_dir_all(DEBUG_LOG_DIR).map_err(|source| RunnerError::CreateDir {
            path: DEBUG_LOG_DIR.into(),
            source,
        })?;

        let log_path = dbus_log_path(program_name, &source_bus_path);
        let log_file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&log_path)
            .map_err(|source| RunnerError::OpenFile {
                path: log_path.clone().into(),
                source,
            })?;

        let log_file_for_stdout = log_file
            .try_clone()
            .map_err(|source| RunnerError::OpenFile {
                path: log_path.clone().into(),
                source,
            })?;

        proxy_cmd.stdout(Stdio::from(log_file_for_stdout));
        proxy_cmd.stderr(Stdio::from(log_file));
    } else {
        proxy_cmd.stdout(Stdio::null());
        proxy_cmd.stderr(Stdio::null());
    }

    for name in &cfg.talk {
        proxy_cmd.arg(format!("--talk={name}"));
    }

    for name in &cfg.own {
        proxy_cmd.arg(format!("--own={name}"));
    }

    for name in &cfg.see {
        proxy_cmd.arg(format!("--see={name}"));
    }

    for (name, iface) in &cfg.call {
        proxy_cmd.arg(format!("--call={name}={iface}"));
    }

    for (name, iface) in &cfg.broadcast {
        proxy_cmd.arg(format!("--broadcast={name}={iface}"));
    }

    let child = proxy_cmd
        .spawn()
        .map_err(|source| RunnerError::SpawnProcess {
            program: if proxy_bin.is_empty() {
                "xdg-dbus-proxy".to_string()
            } else {
                proxy_bin.to_string()
            },
            source,
        })?;

    wait_for_socket(&socket_path)?;

    Ok(ProxyHandle {
        socket_path,
        source_bus_path,
        child,
    })
}

fn wait_for_socket(socket_path: &str) -> Result<(), RunnerError> {
    let max_tries = 500;
    for _ in 0..max_tries {
        if Path::new(socket_path).exists() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(10));
    }

    Err(RunnerError::InvalidConfig(format!(
        "timed out waiting for dbus proxy socket: {socket_path}"
    )))
}

fn host_env_map() -> HashMap<String, String> {
    std::env::vars().collect()
}

fn append_mount_args(
    args: &mut Vec<String>,
    mounts: &[MountRule],
    host_env: &HashMap<String, String>,
    optional_env_vars: &[String],
) -> Result<(), RunnerError> {
    for mount in mounts {
        if references_missing_optional_env_var(&mount.path, host_env, optional_env_vars) {
            continue;
        }

        let path = expand_path_value(&mount.path, host_env)?;
        match mount.perm.as_str() {
            "rw" => {
                if let Some(source) = &mount.source {
                    args.push("--bind-try".to_string());
                    args.push(expand_path_value(source, host_env)?);
                    args.push(path);
                } else {
                    args.push("--bind-try".to_string());
                    args.push(path.clone());
                    args.push(path);
                }
            }
            "ro" => {
                if let Some(source) = &mount.source {
                    args.push("--ro-bind-try".to_string());
                    args.push(expand_path_value(source, host_env)?);
                    args.push(path);
                } else {
                    args.push("--ro-bind-try".to_string());
                    args.push(path.clone());
                    args.push(path);
                }
            }
            "block" => {
                if !Path::new(&path).exists() {
                    continue;
                }

                if mount.r#type == "file" {
                    args.push("--ro-bind".to_string());
                    args.push("/dev/null".to_string());
                    args.push(path);
                } else {
                    args.push("--tmpfs".to_string());
                    args.push(path);
                }
            }
            _ => {}
        }
    }

    Ok(())
}

fn ensure_mount_dirs(
    mounts: &[MountRule],
    host_env: &HashMap<String, String>,
    optional_env_vars: &[String],
) -> Result<(), RunnerError> {
    for mount in mounts {
        if !mount.mkdir || mount.source.is_some() || mount.r#type != "dir" {
            continue;
        }

        if references_missing_optional_env_var(&mount.path, host_env, optional_env_vars) {
            continue;
        }

        let path = expand_path_value(&mount.path, host_env)?;
        fs::create_dir_all(&path).map_err(|source| RunnerError::CreateDir {
            path: path.into(),
            source,
        })?;
    }

    Ok(())
}

fn expand_path_value(
    input: &str,
    env_map: &HashMap<String, String>,
) -> Result<String, RunnerError> {
    expand_value(input, env_map)
}

fn references_env_var(input: &str, name: &str) -> bool {
    [format!("${name}"), format!("${{{name}}}")]
        .iter()
        .any(|needle| input.contains(needle))
}

/// Variables that are allowed to be unset: a mount referencing one of these is
/// skipped entirely rather than erroring (headless session has no
/// `WAYLAND_DISPLAY`, a session with no ssh-agent has no `SSH_AUTH_SOCK`).
/// The list comes from `optionalEnvVars` in `consts.nix`. Every other referenced
/// variable must be defined; see `expand_value`.
fn references_missing_optional_env_var(
    input: &str,
    env_map: &HashMap<String, String>,
    optional_env_vars: &[String],
) -> bool {
    optional_env_vars
        .iter()
        .any(|name| references_env_var(input, name) && !env_map.contains_key(name.as_str()))
}

fn lookup_var<'a>(
    name: &str,
    env_map: &'a HashMap<String, String>,
) -> Result<&'a str, RunnerError> {
    env_map
        .get(name)
        .map(String::as_str)
        .ok_or_else(|| RunnerError::UndefinedVariable {
            name: name.to_string(),
        })
}

/// Substitutes `$VAR` / `${VAR}` from `env_map`. A reference to an undefined
/// variable is a hard error (fail-closed) rather than an empty string. `$$`
/// escapes a literal `$`.
fn expand_value(input: &str, env_map: &HashMap<String, String>) -> Result<String, RunnerError> {
    let mut out = String::new();
    let chars: Vec<char> = input.chars().collect();
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

        // `$$` escapes a literal `$`.
        if chars[i + 1] == '$' {
            out.push('$');
            i += 2;
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
            let key: String = chars[(i + 2)..j].iter().collect();
            out.push_str(lookup_var(&key, env_map)?);
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

        let key: String = chars[(i + 1)..j].iter().collect();
        out.push_str(lookup_var(&key, env_map)?);
        i = j;
    }

    Ok(out)
}

fn replace_runtime_tokens(input: &str) -> String {
    match input {
        "__CURRENT_UID__" => Uid::current().as_raw().to_string(),
        "__CURRENT_GID__" => Gid::current().as_raw().to_string(),
        _ => input.to_string(),
    }
}

fn default_proxy_socket_path() -> String {
    let next_id = NEXT_PROXY_ID.fetch_add(1, Ordering::Relaxed);
    format!(
        "/tmp/dbus-proxy-{}-{}-{}.sock",
        process::id(),
        thread_id_fragment(),
        next_id
    )
}

fn thread_id_fragment() -> String {
    format!("{:?}", thread::current().id()).replace(['(', ')', ' '], "")
}

fn current_dir_fallback() -> String {
    std::env::current_dir()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .unwrap_or_else(|| "/".to_string())
}

fn find_git_root_or_cwd() -> String {
    let cwd = match std::env::current_dir() {
        Ok(path) => path,
        Err(_) => return "/".to_string(),
    };

    resolve_restrict_path(&cwd)
}

/// Walks up from `cwd` to the nearest ancestor containing a `.git` entry and
/// returns it; if none is found, returns `cwd` unchanged.
fn resolve_restrict_path(cwd: &Path) -> String {
    let mut current = cwd;
    loop {
        if current.join(".git").exists() {
            return current
                .to_str()
                .map(|s| s.to_string())
                .unwrap_or_else(|| current_dir_fallback());
        }

        match current.parent() {
            Some(parent) => current = parent,
            None => {
                return cwd
                    .to_str()
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| current_dir_fallback());
            }
        }
    }
}

fn install_signal_forwarders(
    proxy_pids: Arc<Mutex<Vec<i32>>>,
) -> Result<SignalForwarder, RunnerError> {
    let mut signals = Signals::new([SIGINT, SIGTERM, SIGHUP, SIGQUIT])
        .map_err(|source| RunnerError::SignalSetup { source })?;
    let handle = signals.handle();

    let thread = thread::spawn(move || {
        for signal_num in signals.forever() {
            let signal = match Signal::try_from(signal_num) {
                Ok(signal) => signal,
                Err(_) => continue,
            };

            let pids = match proxy_pids.lock() {
                Ok(pids) => pids.clone(),
                Err(_) => Vec::new(),
            };

            for pid in pids {
                if pid > 0 {
                    let _ = kill(Pid::from_raw(pid), signal);
                }
            }
        }
    });

    Ok(SignalForwarder {
        handle,
        thread: Some(thread),
    })
}

fn dbus_log_path(program_name: &str, source_bus_path: &str) -> String {
    format!(
        "{}/{}-dbus-{}.log",
        DEBUG_LOG_DIR,
        sanitize_for_filename(program_name),
        sanitize_for_filename(source_bus_path)
    )
}

fn sanitize_for_filename(input: &str) -> String {
    input
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn shell_escape(input: &str) -> String {
    if !input.is_empty()
        && input
            .bytes()
            .all(|b| matches!(b, b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b'.' | b'_' | b'-' | b':' | b'='))
    {
        return input.to_string();
    }

    let escaped = input.replace('\'', "'\"'\"'");
    format!("'{}'", escaped)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use crate::error::RunnerError;

    use super::*;

    fn env_map() -> HashMap<String, String> {
        HashMap::from([
            ("HOME".to_string(), "/home/test".to_string()),
            ("XDG_RUNTIME_DIR".to_string(), "/run/user/123".to_string()),
            (
                "SSH_AUTH_SOCK".to_string(),
                "/tmp/ssh-agent.sock".to_string(),
            ),
        ])
    }

    fn optional_env_vars() -> Vec<String> {
        vec!["WAYLAND_DISPLAY".to_string(), "SSH_AUTH_SOCK".to_string()]
    }

    #[test]
    fn expands_xdg_runtime_dir_path() {
        assert_eq!(
            expand_path_value("$XDG_RUNTIME_DIR/bus", &env_map()).unwrap(),
            "/run/user/123/bus"
        );
    }

    #[test]
    fn expands_braced_xdg_runtime_dir_path() {
        assert_eq!(
            expand_path_value("${XDG_RUNTIME_DIR}/bus", &env_map()).unwrap(),
            "/run/user/123/bus"
        );
    }

    #[test]
    fn expands_home_path() {
        assert_eq!(
            expand_path_value("$HOME/.config", &env_map()).unwrap(),
            "/home/test/.config"
        );
    }

    #[test]
    fn expands_other_runtime_path_vars() {
        assert_eq!(
            expand_path_value("$SSH_AUTH_SOCK", &env_map()).unwrap(),
            "/tmp/ssh-agent.sock"
        );
    }

    #[test]
    fn detects_missing_optional_wayland_display_path() {
        assert!(references_missing_optional_env_var(
            "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY",
            &env_map(),
            &optional_env_vars()
        ));
    }

    #[test]
    fn detects_missing_optional_ssh_auth_sock_path() {
        let mut env = env_map();
        env.remove("SSH_AUTH_SOCK");
        assert!(references_missing_optional_env_var(
            "$SSH_AUTH_SOCK",
            &env,
            &optional_env_vars()
        ));
        // Present means not "missing optional" -> caller proceeds to expand it.
        assert!(!references_missing_optional_env_var(
            "$SSH_AUTH_SOCK",
            &env_map(),
            &optional_env_vars()
        ));
    }

    #[test]
    fn var_not_in_optional_list_is_not_treated_as_optional() {
        let mut env = env_map();
        env.remove("SSH_AUTH_SOCK");
        // With an empty optional list, a missing var is required (not skipped).
        assert!(!references_missing_optional_env_var(
            "$SSH_AUTH_SOCK",
            &env,
            &[]
        ));
    }

    #[test]
    fn errors_when_referenced_variable_is_undefined() {
        let err = expand_path_value("$NOPE/bus", &env_map()).unwrap_err();
        assert!(matches!(err, RunnerError::UndefinedVariable { name } if name == "NOPE"));
    }

    #[test]
    fn errors_when_xdg_runtime_dir_is_missing() {
        let err = expand_path_value("$XDG_RUNTIME_DIR/bus", &HashMap::new()).unwrap_err();
        assert!(
            matches!(err, RunnerError::UndefinedVariable { name } if name == "XDG_RUNTIME_DIR")
        );
    }

    #[test]
    fn double_dollar_escapes_literal_dollar() {
        assert_eq!(
            expand_value("$$HOME/$HOME", &env_map()).unwrap(),
            "$HOME//home/test"
        );
    }

    // --- append_mount_args: the mount rule -> bwrap arg translation ---

    fn mount(path: &str, perm: &str, ty: &str, source: Option<&str>) -> MountRule {
        MountRule {
            path: path.to_string(),
            perm: perm.to_string(),
            r#type: ty.to_string(),
            source: source.map(|s| s.to_string()),
            mkdir: false,
        }
    }

    fn run_mounts(mounts: &[MountRule]) -> Result<Vec<String>, RunnerError> {
        let mut args = Vec::new();
        append_mount_args(&mut args, mounts, &env_map(), &optional_env_vars())?;
        Ok(args)
    }

    #[test]
    fn rw_mount_without_source_binds_path_to_itself() {
        assert_eq!(
            run_mounts(&[mount("/data", "rw", "dir", None)]).unwrap(),
            vec!["--bind-try", "/data", "/data"]
        );
    }

    #[test]
    fn rw_mount_with_source_binds_source_to_path() {
        assert_eq!(
            run_mounts(&[mount("/data", "rw", "dir", Some("/src"))]).unwrap(),
            vec!["--bind-try", "/src", "/data"]
        );
    }

    #[test]
    fn ro_mount_uses_ro_bind_try() {
        assert_eq!(
            run_mounts(&[mount("/data", "ro", "dir", None)]).unwrap(),
            vec!["--ro-bind-try", "/data", "/data"]
        );
        assert_eq!(
            run_mounts(&[mount("/data", "ro", "dir", Some("/src"))]).unwrap(),
            vec!["--ro-bind-try", "/src", "/data"]
        );
    }

    #[test]
    fn block_dir_on_existing_path_uses_tmpfs() {
        assert_eq!(
            run_mounts(&[mount("/", "block", "dir", None)]).unwrap(),
            vec!["--tmpfs", "/"]
        );
    }

    #[test]
    fn block_file_on_existing_path_binds_dev_null() {
        // /dev/null exists and is a non-directory node.
        assert_eq!(
            run_mounts(&[mount("/dev/null", "block", "file", None)]).unwrap(),
            vec!["--ro-bind", "/dev/null", "/dev/null"]
        );
    }

    #[test]
    fn block_on_nonexistent_path_is_skipped() {
        assert!(run_mounts(&[mount("/nonexistent-zzz-12345", "block", "dir", None)])
            .unwrap()
            .is_empty());
    }

    #[test]
    fn mount_referencing_missing_optional_var_is_skipped() {
        // env_map() has no WAYLAND_DISPLAY, which is in the optional list.
        assert!(
            run_mounts(&[mount("$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY", "rw", "file", None)])
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn mount_path_is_expanded_from_env() {
        assert_eq!(
            run_mounts(&[mount("$XDG_RUNTIME_DIR/wl", "rw", "dir", None)]).unwrap(),
            vec!["--bind-try", "/run/user/123/wl", "/run/user/123/wl"]
        );
    }

    #[test]
    fn mount_with_undefined_required_var_errors() {
        let err = run_mounts(&[mount("$NOPE/x", "rw", "dir", None)]).unwrap_err();
        assert!(matches!(err, RunnerError::UndefinedVariable { name } if name == "NOPE"));
    }

    // --- pure helpers ---

    #[test]
    fn replace_runtime_tokens_replaces_uid_and_gid() {
        assert_eq!(
            replace_runtime_tokens("__CURRENT_UID__"),
            Uid::current().as_raw().to_string()
        );
        assert_eq!(
            replace_runtime_tokens("__CURRENT_GID__"),
            Gid::current().as_raw().to_string()
        );
    }

    #[test]
    fn replace_runtime_tokens_only_matches_whole_string() {
        assert_eq!(
            replace_runtime_tokens("uid=__CURRENT_UID__"),
            "uid=__CURRENT_UID__"
        );
        assert_eq!(replace_runtime_tokens("plain"), "plain");
    }

    #[test]
    fn shell_escape_leaves_simple_strings_unquoted() {
        assert_eq!(shell_escape("/nix/store/abc-1.2.3"), "/nix/store/abc-1.2.3");
        assert_eq!(shell_escape("KEY=value_1"), "KEY=value_1");
    }

    #[test]
    fn shell_escape_quotes_and_escapes_special_strings() {
        assert_eq!(shell_escape("a b"), "'a b'");
        assert_eq!(shell_escape("it's"), "'it'\"'\"'s'");
        assert_eq!(shell_escape(""), "''");
    }

    #[test]
    fn sanitize_for_filename_replaces_disallowed_chars() {
        assert_eq!(sanitize_for_filename("a-b_c1"), "a-b_c1");
        assert_eq!(sanitize_for_filename("unix:path=/run/bus"), "unix_path__run_bus");
    }

    // --- Tier 2: filesystem-touching helpers (tempdirs) ---

    fn unique_temp_dir() -> String {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static COUNTER: AtomicUsize = AtomicUsize::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir()
            .join(format!("nsr-test-{}-{}", std::process::id(), n))
            .to_str()
            .unwrap()
            .to_string()
    }

    #[test]
    fn ensure_mount_dirs_creates_dir_when_mkdir_set() {
        let base = unique_temp_dir();
        let target = format!("{base}/sub/dir");
        let mut m = mount(&target, "rw", "dir", None);
        m.mkdir = true;
        ensure_mount_dirs(&[m], &env_map(), &optional_env_vars()).unwrap();
        assert!(Path::new(&target).is_dir());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn ensure_mount_dirs_skips_when_mkdir_unset() {
        let base = unique_temp_dir();
        let target = format!("{base}/nope");
        ensure_mount_dirs(&[mount(&target, "rw", "dir", None)], &env_map(), &optional_env_vars())
            .unwrap();
        assert!(!Path::new(&target).exists());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn resolve_restrict_path_finds_git_root() {
        let base = unique_temp_dir();
        let repo = format!("{base}/a/b");
        let nested = format!("{repo}/c/d");
        std::fs::create_dir_all(format!("{repo}/.git")).unwrap();
        std::fs::create_dir_all(&nested).unwrap();
        assert_eq!(resolve_restrict_path(Path::new(&nested)), repo);
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn resolve_restrict_path_without_git_returns_input() {
        let base = unique_temp_dir();
        let leaf = format!("{base}/x/y");
        std::fs::create_dir_all(&leaf).unwrap();
        assert_eq!(resolve_restrict_path(Path::new(&leaf)), leaf);
        let _ = std::fs::remove_dir_all(&base);
    }
}
