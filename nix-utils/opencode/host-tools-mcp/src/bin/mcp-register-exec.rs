use anyhow::{bail, Context, Result};
use host_tools_mcp::{register::run_register, RegisteredCommand};

#[tokio::main]
async fn main() -> Result<()> {
    let mut argv = std::env::args().skip(1);
    let executable = argv
        .next()
        .ok_or_else(|| anyhow::anyhow!("usage: mcp-register-exec <executable>"))?;
    if argv.next().is_some() {
        bail!("usage: mcp-register-exec <executable>");
    }
    let mode = RegisteredCommand::exec(executable).context("invalid executable")?;
    run_register(mode).await
}
