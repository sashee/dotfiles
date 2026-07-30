# Machinery case: the host-tools-mcp bridge across the sandbox boundary.
#
# host-tools-mcp is an MCP server spawned INSIDE a sandbox; mcp-register /
# mcp-register-prefix run on the HOST and register a host command as an MCP tool over
# the registry UDS in /tmp/host-tools-mcp (the sandbox opts that dir rw, so the
# in-sandbox server's socket lands in the host-shared dir). When the tool is called, the
# command runs in the host-side provider process — a controlled escape: the sandboxed
# agent can invoke only pre-registered host commands. The Rust e2e tests cover the
# protocol in the build env; this proves the REAL boundary end to end.
#
# The sandbox is the synthetic probe-mcp-client profile, not a real agent's. It used to
# be opencode's, which made this whole case untestable on a machine that skips opencode
# — i.e. exactly the headless box the register channel exists for. That an agent's own
# config points at a working server is asserted per agent in program-opencode.nix /
# program-claude.nix.
#
# The registered command reads /etc/machine-id: the sandbox fakes it, so a tool-call
# result equal to the host's real machine-id proves the command executed on the host,
# not in the sandbox. mcp-register reads its command from stdin and runs it via `sh -c`,
# so the fixed command also carries a `&&` to prove shell syntax survives registration
# and the call.
{ pkgs }:
let
  probeTools = import ../probe-tools { inherit pkgs; };
  hostTools = import ../../host-tools-mcp/default.nix { inherit pkgs; };
  # Store-path node (not /run/current-system/sw/bin/node): the sandbox binds the whole
  # host root ro, so any store path resolves, and this doesn't depend on the machine
  # under test having node in its system profile (nixos-test's aarch64 machine doesn't).
  node = "${pkgs.nodejs}/bin/node";
  mcpClient = ./probes-mcp/mcpClient.js;
  # What the client spawns as the server. Same shape as an agent's MCP config, but owned
  # by the test, so no agent has to be installed for the bridge to be exercised.
  clientConfig = pkgs.writeText "mcp-client-config.json" (builtins.toJSON {
    mcp."host-tools-mcp".command = [ "${hostTools.hostToolsMcp}/bin/host-tools-mcp" ];
  });
  clientShell = probeTools.shell "probe-mcp-client";
  # Runs the node client inside the probe's sandbox; it spawns the MCP server and
  # prints the tool-call result to stdout.
  clientCmd = "MCP_CLIENT_CONFIG=${clientConfig} ${clientShell} -c '${node} ${mcpClient}'";
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
  # mcp-register takes its command on stdin (a shell command, run via `sh -c`);
  # redirecting from a store file sidesteps nested shell quoting in run_user.
  cmdFixed = pkgs.writeText "mcp-cmd-fixed" "cat /etc/machine-id && echo MCP_AND_OK";
  # By store path, not PATH: a machine may skip the host-tools-mcp program, and this is a
  # machinery case — it must not depend on what the machine under test installs.
  mcpRegister = "${hostTools.mcpRegisterBins}/bin/mcp-register";
  mcpRegisterPrefix = "${hostTools.mcpRegisterBins}/bin/mcp-register-prefix";
in
{
  testScript = ''
    host_mid = machine.succeed("cat /etc/machine-id").strip()
    assert len(host_mid) >= 16, f"host machine-id looks wrong: {host_mid!r}"

    # Sanity: the sandbox fakes /etc/machine-id, so the host's real id is a reliable
    # discriminator for host-side (vs in-sandbox) execution.
    sandbox_mid = run_user("${clientShell} -c 'cat /etc/machine-id'").strip()
    assert sandbox_mid and sandbox_mid != host_mid, (
        f"sandbox should fake machine-id (host={host_mid!r} sandbox={sandbox_mid!r})"
    )

    def drive(req, provider, after_broker_link=None):
        run_user("rm -rf /tmp/host-tools-mcp; mkdir -p /tmp/host-tools-mcp")
        run_user("cp " + req + " /tmp/host-tools-mcp/req.json")
        # Start the MCP client INSIDE the probe's sandbox (it spawns host-tools-mcp).
        # nohup + background so it survives the su session exiting; the wrapper
        # writes the result to out/err and the exit code to rc.
        run_user("nohup ${clientRun} >/dev/null 2>&1 &")
        # The in-sandbox server's registry socket appears in the host-shared dir.
        # Race it against the client's rc (written only if the client exits) so a
        # crashed client fails fast with its stderr; on timeout, dump diagnostics
        # instead of a blind wait (node/V8 startup is very slow under aarch64 TCG).
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
        # mcp-register is broker-only and connects to broker_socket_path()
        # (/tmp/host-tools-mcp/broker.sock). No broker here, so symlink that path to
        # the server's registry socket — mcp-register then registers straight to it.
        run_user("ln -sf \"$(ls /tmp/host-tools-mcp/*/registry.sock | head -1)\" /tmp/host-tools-mcp/broker.sock")
        # A caller-supplied precondition on the socket, checked before the provider starts
        # so a failure reports itself instead of surfacing as a provider that never
        # registers (which would only show up as a wait_or_diag timeout much later).
        if after_broker_link is not None:
            after_broker_link()
        # Start the host-side provider: registers a host command and serves calls.
        run_user(
            "nohup " + provider + " >/tmp/host-tools-mcp/prov.out 2>&1 "
            "& echo $! >/tmp/host-tools-mcp/prov.pid"
        )
        # The client lists + calls the tool, prints the result text, and exits;
        # waiting on the exit code (not the output file) means a failed client
        # aborts the test immediately with its stderr instead of timing out.
        wait_or_diag("test -s /tmp/host-tools-mcp/rc", "final rc wait")
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

    # 1) shell tool (mcp-register): command read from stdin, run via `sh -c` on the
    # host — both sides of the `&&` must execute.
    out_fixed = drive("${reqFixed}", "${mcpRegister} <${cmdFixed}")
    assert host_mid in out_fixed, (
        "mcp-register tool call must run on the host and return its real machine-id; "
        f"got {out_fixed!r} (host {host_mid!r})"
    )
    assert "MCP_AND_OK" in out_fixed, (
        "the `&&`-chained second command must run too; "
        f"got {out_fixed!r}"
    )

    # 2) prefix tool (mcp-register-prefix): caller supplies trailing args ["/etc/machine-id"].
    out_prefix = drive("${reqPrefix}", "${mcpRegisterPrefix} cat")
    assert host_mid in out_prefix, (
        "mcp-register-prefix tool call (caller-supplied trailing args) must run on the "
        f"host; got {out_prefix!r} (host {host_mid!r})"
    )

    # 3) Registering from inside the SANDBOXED LOGIN SHELL, which is how a real remote
    # session does it: you ssh in and land in the sandboxed zsh. mcp-register-prefix is a
    # raw bin (not a wrapped tool), so it runs *inside* zsh's own sandbox, and it can only
    # reach the broker socket because zsh's merged fs rules bind /tmp/host-tools-mcp —
    # a binding that reaches zsh solely through host-tools-mcp's sandbox_restrictions
    # (zsh/default.nix folds every zshPrograms entry's fs rules into the shell's sandbox).
    # Drop those rules and this is the assertion that fails.
    #
    # Conditional on the machine shipping the register CLI: a machine that skips the
    # host-tools-mcp program has no CLI to run from its shell, so zsh legitimately has no
    # such binding. Steps 1-2 above stay unconditional — they run the bins by store path.
    if not present("mcp-register-prefix"):
        skip_absent("mcp-register-prefix")
    else:
        def socket_visible_in_zsh():
            run_user("zsh -c 'test -S /tmp/host-tools-mcp/broker.sock'")

        out_zsh = drive(
            "${reqPrefix}",
            "zsh -c '${mcpRegisterPrefix} cat'",
            after_broker_link=socket_visible_in_zsh,
        )
        assert host_mid in out_zsh, (
            "a register run from inside the sandboxed login shell must still reach the broker "
            f"and execute on the host; got {out_zsh!r} (host {host_mid!r})"
        )
  '';
}
