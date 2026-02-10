mod config;
mod error;
mod runtime;

use std::env;
use std::ffi::OsString;
use std::os::unix::ffi::OsStrExt;
use std::process;

use config::{resolve_config_path, RunnerConfig};
use error::RunnerError;

struct Cli {
    config_path: String,
    passthrough_args: Vec<OsString>,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err}");
        process::exit(1);
    }
}

fn run() -> Result<(), RunnerError> {
    let cli = parse_cli(env::args_os().collect())?;
    let config_path = resolve_config_path(&cli.config_path);
    let config = RunnerConfig::from_path(&config_path)?;

    let exit_code = runtime::run(config, cli.passthrough_args)?;
    process::exit(exit_code);
}

fn parse_cli(args: Vec<OsString>) -> Result<Cli, RunnerError> {
    let usage = "nix-sandbox-runner --config <path> [-- <argv...>]".to_string();

    if args.len() < 3 {
        return Err(RunnerError::Usage(usage));
    }

    let mut i = 1usize;
    let mut config_path: Option<String> = None;
    let mut passthrough_args: Vec<OsString> = Vec::new();

    while i < args.len() {
        if args[i].as_os_str().as_bytes() == b"--" {
            passthrough_args.extend(args.into_iter().skip(i + 1));
            break;
        }

        if args[i].as_os_str().as_bytes() == b"--config" {
            let next = args
                .get(i + 1)
                .ok_or_else(|| RunnerError::Usage(usage.clone()))?;
            config_path = Some(
                next.to_str()
                    .ok_or_else(|| {
                        RunnerError::Usage("config path must be valid UTF-8".to_string())
                    })?
                    .to_string(),
            );
            i += 2;
            continue;
        }

        return Err(RunnerError::Usage(usage));
    }

    let config_path = config_path.ok_or_else(|| RunnerError::Usage(usage))?;

    Ok(Cli {
        config_path,
        passthrough_args,
    })
}
