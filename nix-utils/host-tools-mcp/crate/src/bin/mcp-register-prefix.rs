use anyhow::{bail, Context, Result};
use host_tools_mcp::{register::run_register, RegisteredCommand};

#[tokio::main]
async fn main() -> Result<()> {
    let argv = std::env::args().skip(1).collect::<Vec<_>>();
    if argv.is_empty() {
        bail!("usage: mcp-register-prefix <command-prefix> [args...]");
    }
    let mode = RegisteredCommand::argv_prefix(argv).context("invalid command prefix")?;
    run_register(mode).await
}
