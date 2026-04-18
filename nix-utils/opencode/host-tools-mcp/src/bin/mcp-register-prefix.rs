use anyhow::{bail, Context, Result};
use host_tools_mcp::{register::run_register, RegisteredCommand};

#[tokio::main]
async fn main() -> Result<()> {
    let argv = std::env::args().skip(1).collect::<Vec<_>>();
    let (pty, argv) = parse_args(argv)?;
    if argv.is_empty() {
        bail!("usage: mcp-register-prefix [--pty] <command-prefix> [args...]");
    }
    let mode = if pty {
        RegisteredCommand::argv_prefix_pty(argv)
    } else {
        RegisteredCommand::argv_prefix(argv)
    }
    .context("invalid command prefix")?;
    run_register(mode).await
}

fn parse_args(argv: Vec<String>) -> Result<(bool, Vec<String>)> {
    if argv.first().is_some_and(|arg| arg == "--pty") {
        if argv.len() == 1 {
            bail!("usage: mcp-register-prefix [--pty] <command-prefix> [args...]");
        }
        Ok((true, argv[1..].to_vec()))
    } else {
        Ok((false, argv))
    }
}
