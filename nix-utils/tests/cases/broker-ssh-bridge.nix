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
# opencode's sandbox via `opencode-shell -c`, spawning the real server; it polls
# for the `sh_c` tool and calls it. The provider chain that makes `sh_c` appear
# is: server <- broker (host) <- ssh -R <- mcp-register-prefix. The command runs
# in the mcp-register process and its output round-trips back to the client.
#
# Isolated because it needs sshd. Also asserts the launcher auto-start wiring
# (the claude/opencode wrappers invoke `host-tools-mcp-broker --ensure`).
{ pkgs }:
let
  # Store-path node (not /run/current-system/sw/bin/node): the sandbox binds the whole
  # host root ro, so any store path resolves, and this doesn't depend on the machine
  # under test having node in its system profile (nixos-test's aarch64 machine doesn't).
  node = "${pkgs.nodejs}/bin/node";
  mcpClient = ./probes-mcp/mcpClient.js;
  clientCmd = "opencode-shell -c '${node} ${mcpClient}'";
  # Runs the client and records its exit code, so the test can distinguish a
  # still-running client from one that failed (or printed nothing).
  clientRun = pkgs.writeShellScript "mcp-client-run" ''
    ${clientCmd} >/tmp/host-tools-mcp/out 2>/tmp/host-tools-mcp/err
    echo $? >/tmp/host-tools-mcp/rc
  '';
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
    # A long idle grace keeps the broker (which sees no registries here) from
    # idle-exiting before the socket check when `opencode --version` is slow (TCG).
    run_user("HOST_TOOLS_MCP_BROKER_IDLE_MS=600000 timeout 120 opencode --version >/dev/null 2>&1 || true")
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
    #    sh_c, call it, and print the result. Backgrounded so the su session ends;
    #    the wrapper writes the result to out/err and the exit code to rc.
    run_user("nohup ${clientRun} >/dev/null 2>&1 &")
    # Wait for the in-sandbox server's socket, but fail fast if the client exits
    # first (the clientRun wrapper writes rc before any socket exists) — surface
    # its stderr instead of a blind timeout. On success the client stays alive
    # (polling for sh_c) and writes rc only much later, so the socket always wins.
    # Generous timeout: node/V8 startup is pathologically slow under aarch64 TCG.
    wait_or_diag(
        "ls /tmp/host-tools-mcp/*/registry.sock 2>/dev/null "
        "|| test -s /tmp/host-tools-mcp/rc",
        "registry.sock wait",
    )
    if not machine.succeed("ls /tmp/host-tools-mcp/*/registry.sock 2>/dev/null || true").strip():
        dump_mcp_diag("client exited before registry.sock")
        rc = run_user("cat /tmp/host-tools-mcp/rc").strip()
        raise Exception(
            f"mcp client exited (rc={rc}) before creating registry.sock; "
            f"err={run_user('cat /tmp/host-tools-mcp/err 2>/dev/null; true')!r}"
        )

    # 2. Broker on the host: discovers the server, listens on its known socket.
    run_user(
      "nohup host-tools-mcp-broker >/tmp/host-tools-mcp/broker.out 2>&1 "
      "& echo $! >/tmp/host-tools-mcp/broker.pid"
    )
    wait_or_diag("test -S /tmp/host-tools-mcp/broker.sock", "broker.sock wait")

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
    #    and prints the command output. Waiting on the exit code (not the output
    #    file) means a failed client aborts immediately with its stderr instead of
    #    timing out.
    wait_or_diag("test -s /tmp/host-tools-mcp/rc", "final rc wait")
    rc = run_user("cat /tmp/host-tools-mcp/rc").strip()
    out = run_user("cat /tmp/host-tools-mcp/out")
    assert rc == "0" and "BROKER_BRIDGE_OK" in out, (
        "tool call must round-trip through the broker + ssh forward; "
        f"got rc={rc} out={out!r} "
        f"err={run_user('cat /tmp/host-tools-mcp/err 2>/dev/null; true')!r} "
        f"prov={run_user('cat /tmp/host-tools-mcp/prov.out 2>/dev/null; true')!r}"
    )

    run_user("kill $(cat /tmp/host-tools-mcp/prov.pid) 2>/dev/null; true")
    run_user("kill $(cat /tmp/host-tools-mcp/broker.pid) 2>/dev/null; true")
  '';
}
