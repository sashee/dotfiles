# Case: the host-tools-mcp broker reached over a real SSH reverse forward.
#
# This is the end-to-end of the "remote shell" design: a single ssh connection
# reverse-forwards the broker socket; a remote `mcp-register` finds the broker at
# its known socket path (NO env var); the broker fans that registration to the
# live host-tools-mcp server(s) and routes a tool call back.
#
# Single-host caveat: the broker and the forwarded socket can't share one path on
# the same machine, so the "remote" mcp-register uses TMPDIR=/tmp/rem (its
# broker_socket_path becomes /tmp/rem/host-tools-mcp/broker.sock = the forward). On
# two real machines both use the default /tmp and need no TMPDIR. The socket is
# nested in host-tools-mcp/, so the remote dir must exist before `ssh -R` binds it.
#
# We reuse the mcp-bridge harness: an MCP client (mcpClient.js) runs INSIDE
# opencode's sandbox via `opencode-debug -c`, spawning the real server; it polls
# for the `sh_c` tool and calls it. The provider chain that makes `sh_c` appear
# is: server <- broker (host) <- ssh -R <- mcp-register-prefix. The command runs
# in the mcp-register process and its output round-trips back to the client.
#
# Isolated because it needs sshd. Also asserts the launcher auto-start wiring
# (the claude/opencode wrappers invoke `host-tools-mcp-broker --ensure`).
{ pkgs }:
let
  node = "/run/current-system/sw/bin/node";
  mcpClient = ./probes-mcp/mcpClient.js;
  clientCmd = "opencode-debug -c '${node} ${mcpClient}'";
  # Ask the client to call the sh_c tool with a shell command; its stdout proves
  # the call round-tripped through the broker + ssh + mcp-register.
  req = pkgs.writeText "broker-req.json" (builtins.toJSON {
    substr = "sh_c";
    arguments = { args = [ "echo BROKER_BRIDGE_OK" ]; };
  });
  # Absolute path avoids depending on the remote ssh session's PATH.
  regBin = "/run/current-system/sw/bin/mcp-register-prefix";
  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
    + "-o BatchMode=yes -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes";
in
{
  isolate = true;
  machineModules = [ { services.openssh.enable = true; } ];
  testScript = ''
    # --- auto-start wiring: the client launchers invoke the broker --ensure ---
    run_user("grep -q host-tools-mcp-broker $(command -v opencode)")
    run_user("grep -q host-tools-mcp-broker $(command -v claude)")

    # --- auto-start runtime: launching a client actually brings the broker up ---
    # preLaunchHostCmd runs host-side (before the sandbox) -> `host-tools-mcp-broker
    # --ensure` detached, so the broker starts regardless of `opencode --version`.
    run_user("timeout 60 opencode --version >/dev/null 2>&1 || true")
    machine.wait_until_succeeds("test -S /tmp/host-tools-mcp/broker.sock")
    # Reset so this idle broker doesn't interfere with the manual flow below.
    # The `[-]` keeps the pattern from matching this very kill command's own shell.
    run_user("pkill -f 'host-tools-mcp[-]broker' 2>/dev/null; rm -f /tmp/host-tools-mcp/broker.sock; true")

    # --- passwordless ssh to localhost as the test user ---
    run_user("mkdir -p ~/.ssh && chmod 700 ~/.ssh")
    run_user("ssh-keygen -t ed25519 -N ''' -f ~/.ssh/id_ed25519 -q")
    run_user("cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys")

    run_user("rm -rf /tmp/host-tools-mcp; mkdir -p /tmp/host-tools-mcp")
    run_user("cp ${req} /tmp/host-tools-mcp/req.json")

    # 1. MCP client inside opencode's sandbox spawns the server; it will poll for
    #    sh_c, call it, and print the result. Backgrounded so the su session ends.
    run_user(
      "nohup ${clientCmd} >/tmp/host-tools-mcp/out 2>/tmp/host-tools-mcp/err "
      "& echo $! >/tmp/host-tools-mcp/cli.pid"
    )
    machine.wait_until_succeeds("ls /tmp/host-tools-mcp/*/registry.sock 2>/dev/null")

    # 2. Broker on the host: discovers the server, listens on its known socket.
    run_user(
      "nohup host-tools-mcp-broker >/tmp/host-tools-mcp/broker.out 2>&1 "
      "& echo $! >/tmp/host-tools-mcp/broker.pid"
    )
    machine.wait_until_succeeds("test -S /tmp/host-tools-mcp/broker.sock")

    # 3. One ssh connection reverse-forwarding the broker socket to the "remote"
    #    path; mcp-register (TMPDIR=/tmp/rem) finds the broker there — NO env var.
    #    The socket is nested, so the remote dir must exist before `ssh -R` binds.
    run_user("mkdir -p /tmp/rem/host-tools-mcp")
    run_user(
      "nohup ssh ${sshOpts} -R /tmp/rem/host-tools-mcp/broker.sock:/tmp/host-tools-mcp/broker.sock localhost "
      "'TMPDIR=/tmp/rem ${regBin} sh -c' "
      ">/tmp/host-tools-mcp/prov.out 2>&1 & echo $! >/tmp/host-tools-mcp/prov.pid"
    )

    # 4. The client sees sh_c (server <- broker <- ssh <- mcp-register), calls it,
    #    and prints the command output.
    machine.wait_until_succeeds("test -s /tmp/host-tools-mcp/out")
    out = run_user("cat /tmp/host-tools-mcp/out")
    assert "BROKER_BRIDGE_OK" in out, (
        "tool call must round-trip through the broker + ssh forward; "
        f"got out={out!r} prov={run_user('cat /tmp/host-tools-mcp/prov.out || true')!r}"
    )

    run_user("kill $(cat /tmp/host-tools-mcp/prov.pid) 2>/dev/null; true")
    run_user("kill $(cat /tmp/host-tools-mcp/broker.pid) 2>/dev/null; true")
    run_user("kill $(cat /tmp/host-tools-mcp/cli.pid) 2>/dev/null; true")
  '';
}
