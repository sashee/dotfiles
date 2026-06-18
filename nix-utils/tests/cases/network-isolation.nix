# Case: tools without network=true cannot use the network — enforced by seccomp
# (socket(AF_INET) -> EACCES) plus `--unshare-net`. `node` has network; `node-nonet`
# does not. Tested two ways on one machine: socket creation, and end-to-end reach
# to a loopback listener (the listener is the wrapped `node` itself, since it shares
# the VM net namespace — machine-agnostic, no machine config needed).
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    # Socket creation: node-nonet can't even create an AF_INET socket; node can.
    run_user("node ${probes.bindUdp}")                       # control: binds OK
    run_user("node-nonet ${probes.bindUdp}", succeed=False)  # seccomp EACCES

    # End-to-end: a background listener on 127.0.0.1:8123 (run by `node`, which
    # shares the VM netns), then connect from both tools.
    run_user("(node ${probes.server} 127.0.0.1 8123 >/tmp/nsr-srv.log 2>&1 & echo $! > /tmp/nsr-srv.pid)")
    machine.wait_until_succeeds("ss -tln | grep -q ':8123'")

    out = run_user("node ${probes.connect} 127.0.0.1 8123")
    assert "connected" in out, f"node should reach the loopback listener, got: {out!r}"

    # node-nonet has its own empty netns (+ seccomp) -> cannot connect.
    run_user("node-nonet ${probes.connect} 127.0.0.1 8123", succeed=False)

    # Kill by recorded PID (pkill -f on the store path would also match this very
    # cleanup command's argv and SIGTERM its own shell).
    run_user("kill $(cat /tmp/nsr-srv.pid) 2>/dev/null || true")
    run_user("rm -f /tmp/nsr-srv.pid /tmp/nsr-srv.log")
  '';
}
