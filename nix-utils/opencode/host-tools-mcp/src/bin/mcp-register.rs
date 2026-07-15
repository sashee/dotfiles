use std::io::{IsTerminal, Read, Write};

use anyhow::{bail, Context, Result};
use host_tools_mcp::{register::run_register, RegisteredCommand};

// The command is read from stdin, not argv: the interactive shell would parse
// `&&`, pipes, redirects etc. out of an argv invocation before we ever see them.
fn read_command() -> Result<String> {
    let mut stdin = std::io::stdin();
    let mut input = String::new();
    if stdin.is_terminal() {
        eprint!("command: ");
        std::io::stderr().flush()?;
        stdin.read_line(&mut input).context("failed to read command")?;
    } else {
        stdin
            .read_to_string(&mut input)
            .context("failed to read command")?;
    }
    Ok(input.trim().to_string())
}

#[tokio::main]
async fn main() -> Result<()> {
    if std::env::args().len() > 1 {
        bail!("mcp-register takes no arguments; run it and paste the command at the prompt");
    }
    let command = read_command()?;
    if command.is_empty() {
        bail!("no command given");
    }
    let mode = RegisteredCommand::shell(command).context("invalid command")?;
    run_register(mode).await
}
