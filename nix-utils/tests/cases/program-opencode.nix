# Per-program case: opencode's own MCP wiring, asserted only if this machine installs it
# (a headless box can skip the agent and keep just the host-tools-mcp CLIs). The bridge
# machinery itself — server in a sandbox, host-side register, broker, ssh forward — is
# covered by mcp-bridge.nix / remote-register.nix under synthetic probes, so skipping
# here loses only opencode's own wiring.
#
# What must hold for opencode specifically, none of it derivable from its config:
#   - Its launcher invokes `host-tools-mcp-broker --ensure` before the sandbox starts
#     (preLaunchHostCmd), so a client launch brings the broker up by itself.
#   - The MCP server command in its injected config actually exists and is executable —
#     the config is what the real agent follows to spawn the server.
#   - Launching it really does bring the broker socket up, not just declare the intent.
{ pkgs }:
{
  testScript = ''
    if not present("opencode"):
        skip_absent("opencode")
    else:
        # 1) The wrapper carries the broker auto-start (preLaunchHostCmd).
        run_user("grep -q host-tools-mcp-broker $(command -v opencode)")

        # 2) The injected config names an executable MCP server. jq over $OPENCODE_CONFIG
        # from inside the sandbox, where the launcher's setEnv applies.
        server = run_user(
            "opencode-shell -c '${pkgs.jq}/bin/jq -r \".mcp[\\\"host-tools-mcp\\\"].command[0]\" \"$OPENCODE_CONFIG\"'"
        ).strip()
        assert server.startswith("/nix/store/"), (
            f"opencode's config must name the MCP server by store path; got {server!r}"
        )
        run_user(f"test -x {server}")

        # 3) Launching opencode actually starts the broker. A long idle grace keeps the
        # broker (which sees no registries here) from idle-exiting before the check when
        # `opencode --version` is slow under aarch64 TCG.
        run_user("rm -f /tmp/host-tools-mcp/broker.sock; true")
        run_user("HOST_TOOLS_MCP_BROKER_IDLE_MS=600000 timeout 120 opencode --version >/dev/null 2>&1 || true")
        machine.wait_until_succeeds("test -S /tmp/host-tools-mcp/broker.sock")
        # Leave no idle broker behind for the next case. The `[-]` keeps the pattern from
        # matching this very kill command's own shell.
        run_user("pkill -f 'host-tools-mcp[-]broker' 2>/dev/null; rm -f /tmp/host-tools-mcp/broker.sock; true")
  '';
}
