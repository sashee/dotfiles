# Per-program case: claude's own MCP wiring and secret handling, asserted only if this
# machine installs it (hosts/rpi5 skips claude). The bridge machinery is covered by
# mcp-bridge.nix / remote-register.nix under synthetic probes, and env scrubbing as a
# mechanism by env-scrubbing.nix, so skipping here loses only claude's own assertions.
#
# What must hold for claude specifically:
#   - Its launcher invokes `host-tools-mcp-broker --ensure` before the sandbox starts.
#   - Unlike opencode there is no config env var: claude gets `--mcp-config <file>` baked
#     into its entry script, so the chain to check is entry script -> mcp.json ->
#     mcpServers."host-tools-mcp".command, and that command must be executable.
#   - Host credentials must not reach the agent's sandbox. claude's keepEnv lists no
#     credential vars, and that is a security property of THIS program's config, not of
#     the scrubbing mechanism.
{ pkgs }:
let
  jq = "${pkgs.jq}/bin/jq";
  printenv = "${pkgs.coreutils}/bin/printenv";
in
{
  testScript = ''
    if not present("claude"):
        skip_absent("claude")
    else:
        # 1) The wrapper carries the broker auto-start (preLaunchHostCmd).
        run_user("grep -q host-tools-mcp-broker $(command -v claude)")

        # 2) Follow the config chain to the MCP server binary. claude-info reports the
        # launcher's target (the entry script), which carries the --mcp-config path.
        target = run_user("claude-info 2>/dev/null | ${jq} -r '.configured.launcher_args.target'").strip()
        assert target.startswith("/nix/store/"), f"claude's launcher target looks wrong: {target!r}"
        mcp_cfg = run_user(
            f"grep -o -- '--mcp-config [^ ]*' {target} | head -1 | cut -d' ' -f2"
        ).strip()
        assert mcp_cfg.startswith("/nix/store/"), (
            f"claude's entry script must pass --mcp-config <store path>; got {mcp_cfg!r}"
        )
        server = run_user("${jq} -r '.mcpServers[\"host-tools-mcp\"].command' " + mcp_cfg).strip()
        assert server.startswith("/nix/store/"), (
            f"claude's mcp config must name the host-tools-mcp server by store path; got {server!r}"
        )
        run_user(f"test -x {server}")

        # 3) Host credentials do not reach the agent's sandbox.
        env = run_user(
            "NIXUTILS_SECRET=leaked-do-not-pass AWS_ACCESS_KEY_ID=AKIAFAKELEAKTEST "
            "claude-shell -c '${printenv}'"
        )
        assert "leaked-do-not-pass" not in env, "claude must scrub NIXUTILS_SECRET (not in its keepEnv)"
        assert "AKIAFAKELEAKTEST" not in env, (
            "claude must NOT leak the host AWS_ACCESS_KEY_ID into the agent sandbox"
        )
  '';
}
