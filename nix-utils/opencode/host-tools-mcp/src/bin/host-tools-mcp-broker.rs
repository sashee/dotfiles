//! Host-side multiplexing broker for `host-tools-mcp` (see `broker` module).
//!
//! Usage:
//!   host-tools-mcp-broker            run in the foreground until idle-exit
//!   host-tools-mcp-broker --ensure   no-op if a broker is already running,
//!                                    otherwise run (intended to be launched
//!                                    detached, e.g. `setsid -f ... --ensure`).
//!
//! Detachment is left to the caller (`setsid -f` in the client launcher) so this
//! binary stays free of `unsafe` (the crate denies it).

use anyhow::Result;
use host_tools_mcp::broker::{broker_socket_path, run_broker};

#[tokio::main]
async fn main() -> Result<()> {
    let ensure = std::env::args().skip(1).any(|arg| arg == "--ensure");
    let socket_path = broker_socket_path();

    // Singleton: if a broker already accepts connections, this invocation is a
    // fast no-op. (run_broker's bind also guards the race of two concurrent starts.)
    if ensure && std::os::unix::net::UnixStream::connect(&socket_path).is_ok() {
        return Ok(());
    }

    run_broker(socket_path).await
}
