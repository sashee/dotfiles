use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::io;
use std::process::{Child, Command, Stdio};

use serde::Deserialize;
use serde::Serialize;
use serde_json::Map;
use serde_json::Value;
use thiserror::Error;

const MAX_PARALLEL: usize = 10;

#[derive(Debug, Error)]
enum AllInfoError {
    #[error("usage: nix-sandbox-all-info --config <path> --mode <json|table-json>")]
    Usage,

    #[error("failed to read config {path}: {source}")]
    ReadConfig { path: String, source: io::Error },

    #[error("invalid JSON in config {path}: {source}")]
    ParseConfig {
        path: String,
        source: serde_json::Error,
    },

    #[error("failed to spawn {name} ({path}): {source}")]
    Spawn {
        name: String,
        path: String,
        source: io::Error,
    },

    #[error("failed to wait for {name} ({path}): {source}")]
    Wait {
        name: String,
        path: String,
        source: io::Error,
    },

    #[error("{name} ({path}) failed with exit code {code}\n{stderr}")]
    CommandFailed {
        name: String,
        path: String,
        code: i32,
        stderr: String,
    },

    #[error("{name} ({path}) terminated by signal\n{stderr}")]
    CommandSignaled {
        name: String,
        path: String,
        stderr: String,
    },

    #[error("{name} ({path}) returned empty output")]
    EmptyOutput { name: String, path: String },

    #[error("{name} ({path}) returned invalid JSON: {source}")]
    ParseOutput {
        name: String,
        path: String,
        source: serde_json::Error,
    },

    #[error("{name} ({path}) output is missing required fields")]
    InvalidOutputShape { name: String, path: String },

    #[error("failed to serialize output: {0}")]
    Serialize(serde_json::Error),
}

#[derive(Debug, Clone, Deserialize)]
struct ScriptConfig {
    name: String,
    path: String,
}

#[derive(Debug)]
enum Mode {
    Json,
    TableJson,
}

#[derive(Debug)]
struct Cli {
    config_path: String,
    mode: Mode,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct InfoSeccomp {
    inet_blocked: bool,
    inet6_blocked: bool,
    unix_blocked: bool,
    netlink_blocked: bool,
    packet_blocked: bool,
    bluetooth_blocked: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct InfoShare {
    user: bool,
    uts: bool,
    cgroup: bool,
    pid: bool,
    ipc: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct InfoDoc {
    name: String,
    unix_sockets: Vec<String>,
    network_access: bool,
    real_dev: bool,
    seccomp: InfoSeccomp,
    share: InfoShare,
    protected_paths: BTreeMap<String, bool>,
}

#[derive(Debug, Serialize)]
struct TableRow {
    name: String,
    network_access: bool,
    real_dev: bool,
    seccomp_bitmap: String,
    seccomp: InfoSeccomp,
    share_bitmap: String,
    share: InfoShare,
    protected_paths_bitmap: String,
    protected_paths: BTreeMap<String, bool>,
}

#[derive(Debug)]
struct CommandRun {
    index: usize,
    name: String,
    path: String,
    child: Child,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), AllInfoError> {
    let cli = parse_cli(std::env::args_os().collect())?;
    let scripts = read_config(&cli.config_path)?;
    let outputs = run_scripts_capped(&scripts)?;

    let out = match cli.mode {
        Mode::Json => render_json_map(&outputs)?,
        Mode::TableJson => render_table_json(&outputs)?,
    };

    println!("{out}");
    Ok(())
}

fn parse_cli(args: Vec<OsString>) -> Result<Cli, AllInfoError> {
    if args.len() != 5 {
        return Err(AllInfoError::Usage);
    }

    if args[1].to_string_lossy() != "--config" || args[3].to_string_lossy() != "--mode" {
        return Err(AllInfoError::Usage);
    }

    let config_path = args[2].to_string_lossy().to_string();
    let mode = match args[4].to_string_lossy().as_ref() {
        "json" => Mode::Json,
        "table-json" => Mode::TableJson,
        _ => return Err(AllInfoError::Usage),
    };

    Ok(Cli { config_path, mode })
}

fn read_config(path: &str) -> Result<Vec<ScriptConfig>, AllInfoError> {
    let content = fs::read_to_string(path).map_err(|source| AllInfoError::ReadConfig {
        path: path.to_string(),
        source,
    })?;

    serde_json::from_str(&content).map_err(|source| AllInfoError::ParseConfig {
        path: path.to_string(),
        source,
    })
}

fn run_scripts_capped(scripts: &[ScriptConfig]) -> Result<Vec<InfoDoc>, AllInfoError> {
    let mut results: Vec<Option<InfoDoc>> = vec![None; scripts.len()];

    for (chunk_idx, chunk) in scripts.chunks(MAX_PARALLEL).enumerate() {
        let chunk_base = chunk_idx * MAX_PARALLEL;
        let mut running = Vec::with_capacity(chunk.len());

        for (offset, script) in chunk.iter().enumerate() {
            let child = Command::new(&script.path)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|source| AllInfoError::Spawn {
                    name: script.name.clone(),
                    path: script.path.clone(),
                    source,
                })?;

            let index = chunk_base + offset;

            running.push(CommandRun {
                index,
                name: script.name.clone(),
                path: script.path.clone(),
                child,
            });
        }

        for run in running {
            let output = run
                .child
                .wait_with_output()
                .map_err(|source| AllInfoError::Wait {
                    name: run.name.clone(),
                    path: run.path.clone(),
                    source,
                })?;

            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

            if !output.status.success() {
                if let Some(code) = output.status.code() {
                    return Err(AllInfoError::CommandFailed {
                        name: run.name,
                        path: run.path,
                        code,
                        stderr,
                    });
                }

                return Err(AllInfoError::CommandSignaled {
                    name: run.name,
                    path: run.path,
                    stderr,
                });
            }

            if output.stdout.is_empty() {
                return Err(AllInfoError::EmptyOutput {
                    name: run.name,
                    path: run.path,
                });
            }

            let value: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
                AllInfoError::ParseOutput {
                    name: run.name.clone(),
                    path: run.path.clone(),
                    source,
                }
            })?;

            let info: InfoDoc =
                serde_json::from_value(value).map_err(|_| AllInfoError::InvalidOutputShape {
                    name: run.name.clone(),
                    path: run.path.clone(),
                })?;

            results[run.index] = Some(info);
        }
    }

    let mut out = Vec::with_capacity(scripts.len());
    for (i, result) in results.into_iter().enumerate() {
        let item = result.ok_or_else(|| AllInfoError::InvalidOutputShape {
            name: scripts[i].name.clone(),
            path: scripts[i].path.clone(),
        })?;
        out.push(item);
    }

    Ok(out)
}

fn render_json_map(outputs: &[InfoDoc]) -> Result<String, AllInfoError> {
    let mut by_name = Map::new();
    for doc in outputs {
        let value = serde_json::to_value(doc).map_err(AllInfoError::Serialize)?;
        by_name.insert(doc.name.clone(), value);
    }

    serde_json::to_string_pretty(&Value::Object(by_name)).map_err(AllInfoError::Serialize)
}

fn render_table_json(outputs: &[InfoDoc]) -> Result<String, AllInfoError> {
    let mut rows: Vec<TableRow> = outputs
        .iter()
        .map(|doc| TableRow {
            name: doc.name.clone(),
            network_access: doc.network_access,
            real_dev: doc.real_dev,
            seccomp_bitmap: seccomp_bitmap(&doc.seccomp),
            seccomp: doc.seccomp.clone(),
            share_bitmap: share_bitmap(&doc.share),
            share: doc.share.clone(),
            protected_paths_bitmap: protected_paths_bitmap(&doc.protected_paths),
            protected_paths: doc.protected_paths.clone(),
        })
        .collect();

    rows.sort_by(|a, b| a.name.cmp(&b.name));
    serde_json::to_string_pretty(&rows).map_err(AllInfoError::Serialize)
}

fn seccomp_bitmap(seccomp: &InfoSeccomp) -> String {
    [
        seccomp.inet_blocked,
        seccomp.inet6_blocked,
        seccomp.unix_blocked,
        seccomp.netlink_blocked,
        seccomp.packet_blocked,
        seccomp.bluetooth_blocked,
    ]
    .iter()
    .map(|blocked| if *blocked { ' ' } else { 'X' })
    .collect()
}

fn share_bitmap(share: &InfoShare) -> String {
    [share.user, share.uts, share.cgroup, share.pid, share.ipc]
        .iter()
        .map(|enabled| if *enabled { 'X' } else { ' ' })
        .collect()
}

fn protected_paths_bitmap(paths: &BTreeMap<String, bool>) -> String {
    paths
        .values()
        .map(|visible| if *visible { 'X' } else { ' ' })
        .collect()
}
