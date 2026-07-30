# Machinery case: registering a host command from a SECOND machine, over a real ssh
# reverse forward, and calling it as an MCP tool from the first.
#
# This is the end-to-end of the "remote shell" design, in its real topology:
#
#   machine (laptop)                                   remote (rpi)
#   ---------------------------------------            ---------------------------
#   MCP client in probe-mcp-client's sandbox
#     -> spawns host-tools-mcp (the server)
#   broker on /tmp/host-tools-mcp/broker.sock  <--ssh -R--  mcp-register-prefix cat
#                                                           (from the remote's PATH)
#
# The remote node installs ONLY the host-tools-mcp program: no opencode, no claude, no
# rest-of-env. That is the configuration this channel exists for — a headless box you ssh
# into to register host commands — and asserting the agents are absent is what stops this
# test from passing for the wrong reason.
#
# Two machines mean two things the old single-host version (ssh to localhost) could not do:
#   - both sides use the DEFAULT ${TMPDIR:-/tmp}/host-tools-mcp/broker.sock path. On one
#     host the broker and the forwarded socket collide there, which forced a TMPDIR=/tmp/rem
#     workaround that no real deployment has.
#   - the registered command's output proves WHERE it ran: /tmp/where holds a different
#     marker on each node, so a tool result of REMOTE_SIDE_OK can only have come from the
#     remote. Locally it would have read LAPTOP_SIDE.
#
# Isolated because it needs sshd and a second node.
{ pkgs }:
let
  probeTools = import ../probe-tools { inherit pkgs; };
  hostTools = import ../../host-tools-mcp/default.nix { inherit pkgs; };

  remoteUser = "remoteuser";
  remoteMarker = "REMOTE_SIDE_OK";
  laptopMarker = "LAPTOP_SIDE";
  markerPath = "/tmp/where";

  # Store-path node (not /run/current-system/sw/bin/node): the sandbox binds the whole
  # host root ro, so any store path resolves, and this doesn't depend on the machine
  # under test having node in its system profile (nixos-test's aarch64 machine doesn't).
  node = "${pkgs.nodejs}/bin/node";
  mcpClient = ./probes-mcp/mcpClient.js;
  # What the client spawns as the server — the test's own config, not an agent's.
  clientConfig = pkgs.writeText "mcp-client-config.json" (builtins.toJSON {
    mcp."host-tools-mcp".command = [ "${hostTools.hostToolsMcp}/bin/host-tools-mcp" ];
  });
  clientCmd = "MCP_CLIENT_CONFIG=${clientConfig} ${probeTools.shell "probe-mcp-client"} -c '${node} ${mcpClient}'";
  # Runs the client and records its exit code, so the test can distinguish a
  # still-running client from one that failed (or printed nothing).
  clientRun = pkgs.writeShellScript "mcp-client-run" ''
    ${clientCmd} >/tmp/host-tools-mcp/out 2>/tmp/host-tools-mcp/err
    echo $? >/tmp/host-tools-mcp/rc
  '';
  # Ask the client to call the registered prefix tool with the marker path as the trailing
  # argument; its stdout is then whichever machine's marker file got read.
  req = pkgs.writeText "remote-req.json" (builtins.toJSON {
    substr = "cat";
    arguments = { args = [ markerPath ]; };
  });

  # Store paths for the LAPTOP side: this case must not depend on the machine under test
  # installing host-tools-mcp (a machine may skip it). The REMOTE side deliberately uses
  # its own PATH — that it has the CLI installed is part of what's under test.
  brokerBin = "${hostTools.mcpRegisterBins}/bin/host-tools-mcp-broker";
  ssh = "${pkgs.openssh}/bin/ssh";
  sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
    + "-o BatchMode=yes -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes";
in
{
  isolate = true;
  # Ceiling, not a wait: two nodes, and the rpi variant runs under TCG emulation on the
  # KVM-less aarch64 CI runner.
  globalTimeout = 2400;
  nodes.remote = { ... }: {
    services.openssh.enable = true;
    users.users.${remoteUser} = {
      isNormalUser = true;
      uid = 1000;
    };
    # ONLY the register CLIs + broker — deliberately no agent and no rest-of-env, so a
    # pass here means the registration channel needs nothing else installed.
    environment.systemPackages = hostTools.scripts;
    # Small workload (sshd + one Rust process): keep the two-node test inside the 4 GB Pi.
    virtualisation.memorySize = 512;
    system.stateVersion = pkgs.lib.trivial.release;
  };
  testScript = ''
    remote.start()
    remote.wait_for_unit("sshd.service")

    # --- the remote is genuinely agent-free, and does have the register CLI ---
    remote.fail("command -v opencode")
    remote.fail("command -v claude")
    remote.succeed("command -v mcp-register-prefix")

    # --- markers: a tool result can only match the machine it actually ran on ---
    remote.succeed("echo ${remoteMarker} > ${markerPath}")
    machine.succeed("echo ${laptopMarker} > ${markerPath}")

    # --- passwordless ssh from the machine under test to the remote ---
    run_user("mkdir -p ~/.ssh && chmod 700 ~/.ssh")
    run_user("ssh-keygen -t ed25519 -N ''' -f ~/.ssh/id_ed25519 -q")
    pubkey = run_user("cat ~/.ssh/id_ed25519.pub").strip()
    remote.succeed(
        "install -d -m 0700 -o ${remoteUser} -g users /home/${remoteUser}/.ssh && "
        f"printf '%s\\n' '{pubkey}' > /home/${remoteUser}/.ssh/authorized_keys && "
        "chown ${remoteUser}:users /home/${remoteUser}/.ssh/authorized_keys && "
        "chmod 0600 /home/${remoteUser}/.ssh/authorized_keys"
    )
    # The broker socket is nested in host-tools-mcp/, so the remote dir must exist (and be
    # writable by the ssh user) before `ssh -R` can bind inside it.
    remote.succeed("mkdir -p /tmp/host-tools-mcp && chown ${remoteUser} /tmp/host-tools-mcp")

    run_user("rm -rf /tmp/host-tools-mcp; mkdir -p /tmp/host-tools-mcp")
    run_user("cp ${req} /tmp/host-tools-mcp/req.json")

    # 1. MCP client in the probe's sandbox spawns the server; it will poll for the tool,
    #    call it, and print the result. Backgrounded so the su session ends; the wrapper
    #    writes the result to out/err and the exit code to rc.
    run_user("nohup ${clientRun} >/dev/null 2>&1 &")
    # Wait for the in-sandbox server's socket, but fail fast if the client exits first (the
    # clientRun wrapper writes rc before any socket exists) — surface its stderr instead of
    # a blind timeout. Generous: node/V8 startup is very slow under aarch64 TCG.
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

    # 2. Broker on the laptop: discovers the server, listens on its known socket.
    run_user(
      "nohup ${brokerBin} >/tmp/host-tools-mcp/broker.out 2>&1 "
      "& echo $! >/tmp/host-tools-mcp/broker.pid"
    )
    wait_or_diag("test -S /tmp/host-tools-mcp/broker.sock", "broker.sock wait")

    # 3. One ssh connection reverse-forwards the broker socket to the SAME default path on
    #    the remote, where the remote's own mcp-register-prefix finds it with no env var.
    run_user(
      "nohup ${ssh} ${sshOpts} "
      "-R /tmp/host-tools-mcp/broker.sock:/tmp/host-tools-mcp/broker.sock "
      "${remoteUser}@remote 'mcp-register-prefix cat' "
      ">/tmp/host-tools-mcp/prov.out 2>&1 & echo $! >/tmp/host-tools-mcp/prov.pid"
    )

    # 4. The client sees the tool (server <- broker <- ssh <- remote mcp-register), calls it
    #    with the marker path, and prints what the REMOTE read.
    try:
        wait_or_diag("test -s /tmp/host-tools-mcp/rc", "final rc wait")
    except Exception:
        print("=== remote journal (the register process runs there) ===")
        print(remote.execute("journalctl -b --no-pager | tail -n 40")[1])
        raise
    rc = run_user("cat /tmp/host-tools-mcp/rc").strip()
    out = run_user("cat /tmp/host-tools-mcp/out")
    assert rc == "0" and "${remoteMarker}" in out, (
        "the tool call must round-trip through the broker + ssh forward to the remote; "
        f"got rc={rc} out={out!r} "
        f"err={run_user('cat /tmp/host-tools-mcp/err 2>/dev/null; true')!r} "
        f"prov={run_user('cat /tmp/host-tools-mcp/prov.out 2>/dev/null; true')!r}"
    )
    assert "${laptopMarker}" not in out, (
        "the registered command must have run on the REMOTE machine, but the result carries "
        f"the laptop's marker: {out!r}"
    )

    run_user("kill $(cat /tmp/host-tools-mcp/prov.pid) 2>/dev/null; true")
    run_user("kill $(cat /tmp/host-tools-mcp/broker.pid) 2>/dev/null; true")
  '';
}
