# Case: the host-tools-mcp bridge across the sandbox boundary.
#
# host-tools-mcp is an MCP server spawned INSIDE opencode's sandbox; mcp-register /
# mcp-register-prefix run on the HOST and register a host command as an MCP tool over
# the registry UDS in /tmp/host-tools-mcp (opencode opts that dir rw, so the in-sandbox
# server's socket lands in the host-shared dir). When the tool is called, the command
# runs in the host-side provider process — a controlled escape: the sandboxed agent can
# invoke only pre-registered host commands. The Rust e2e tests cover the protocol in the
# build env; this proves the REAL boundary end to end.
#
# We drive the server with a node MCP client (mcpClient.js) run via `opencode-debug -c`,
# so the client + server both live in opencode's actual sandbox. The client self-
# discovers the server from $OPENCODE_CONFIG. The registered command is `cat
# /etc/machine-id`: the sandbox fakes /etc/machine-id, so a tool-call result equal to the
# host's real machine-id proves the command executed on the host, not in the sandbox.
{ pkgs }:
let
  node = "/run/current-system/sw/bin/node";
  mcpClient = ./probes-mcp/mcpClient.js;
  # opencode-debug runs the node client inside opencode's sandbox; it spawns the MCP
  # server (from $OPENCODE_CONFIG) and prints the tool-call result to stdout.
  clientCmd = "opencode-debug -c '${node} ${mcpClient}'";
  # Runs the client and records its exit code, so the test can distinguish a
  # still-running client from one that failed (or printed nothing) and react
  # instead of spinning against an output file until the harness timeout.
  clientRun = pkgs.writeShellScript "mcp-client-run" ''
    ${clientCmd} >/tmp/host-tools-mcp/out 2>/tmp/host-tools-mcp/err
    echo $? >/tmp/host-tools-mcp/rc
  '';
  # The client's request (which tool, which arguments), placed in the rw-shared dir so no
  # shell-quoting is needed. "cat" matches the sanitized tool name of both registrations.
  reqFixed = pkgs.writeText "mcp-req-fixed.json" (builtins.toJSON { substr = "cat"; arguments = { }; });
  reqPrefix = pkgs.writeText "mcp-req-prefix.json" (builtins.toJSON { substr = "cat"; arguments = { args = [ "/etc/machine-id" ]; }; });
in
{
  testScript = ''
    host_mid = machine.succeed("cat /etc/machine-id").strip()
    assert len(host_mid) >= 16, f"host machine-id looks wrong: {host_mid!r}"

    # Sanity: opencode's sandbox fakes /etc/machine-id, so the host's real id is a
    # reliable discriminator for host-side (vs in-sandbox) execution.
    sandbox_mid = run_user("opencode-debug -c 'cat /etc/machine-id'").strip()
    assert sandbox_mid and sandbox_mid != host_mid, (
        f"sandbox should fake machine-id (host={host_mid!r} sandbox={sandbox_mid!r})"
    )

    def drive(req, provider):
        run_user("rm -rf /tmp/host-tools-mcp; mkdir -p /tmp/host-tools-mcp")
        run_user("cp " + req + " /tmp/host-tools-mcp/req.json")
        # Start the MCP client INSIDE opencode's sandbox (it spawns host-tools-mcp).
        # nohup + background so it survives the su session exiting; the wrapper
        # writes the result to out/err and the exit code to rc.
        run_user("nohup ${clientRun} >/dev/null 2>&1 &")
        # The in-sandbox server's registry socket appears in the host-shared dir.
        machine.wait_until_succeeds("ls /tmp/host-tools-mcp/*/registry.sock 2>/dev/null")
        # mcp-register is broker-only and connects to broker_socket_path()
        # (/tmp/host-tools-mcp/broker.sock). No broker here, so symlink that path to
        # the server's registry socket — mcp-register then registers straight to it.
        run_user("ln -sf \"$(ls /tmp/host-tools-mcp/*/registry.sock | head -1)\" /tmp/host-tools-mcp/broker.sock")
        # Start the host-side provider: registers a host command and serves calls.
        run_user(
            "nohup " + provider + " >/tmp/host-tools-mcp/prov.out 2>&1 "
            "& echo $! >/tmp/host-tools-mcp/prov.pid"
        )
        # The client lists + calls the tool, prints the result text, and exits;
        # waiting on the exit code (not the output file) means a failed client
        # aborts the test immediately with its stderr instead of timing out.
        machine.wait_until_succeeds("test -s /tmp/host-tools-mcp/rc")
        rc = run_user("cat /tmp/host-tools-mcp/rc").strip()
        out = run_user("cat /tmp/host-tools-mcp/out")
        if rc != "0" or not out.strip():
            err = run_user("cat /tmp/host-tools-mcp/err 2>/dev/null; true")
            prov = run_user("cat /tmp/host-tools-mcp/prov.out 2>/dev/null; true")
            raise Exception(
                f"mcp client failed: rc={rc} out={out!r} err={err!r} prov={prov!r}"
            )
        run_user("kill $(cat /tmp/host-tools-mcp/prov.pid) 2>/dev/null; true")
        return out

    # 1) fixed-argv tool (mcp-register): runs the exact `cat /etc/machine-id` on the host.
    out_fixed = drive("${reqFixed}", "mcp-register cat /etc/machine-id")
    assert host_mid in out_fixed, (
        "mcp-register tool call must run on the host and return its real machine-id; "
        f"got {out_fixed!r} (host {host_mid!r})"
    )

    # 2) prefix tool (mcp-register-prefix): caller supplies trailing args ["/etc/machine-id"].
    out_prefix = drive("${reqPrefix}", "mcp-register-prefix cat")
    assert host_mid in out_prefix, (
        "mcp-register-prefix tool call (caller-supplied trailing args) must run on the "
        f"host; got {out_prefix!r} (host {host_mid!r})"
    )
  '';
}
