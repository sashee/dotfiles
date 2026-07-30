# Machinery case: the seccomp socket-family filter. The runner fails socket(family)
# with EACCES for blocked families. Four profiles, each carried by a synthetic probe
# (see ../probe-tools) rather than by whichever real tool happens to be configured that
# way — the mechanism is what's under test, and it must be assertable on any machine:
#   - probe-default:      no `network` -> autoBlock inet/inet6, unix still allowed.
#   - probe-unix-blocked: autoBlock + an explicit AF_UNIX block -> unix refused too.
#   - probe-inet-blocked: `network=true` (shares the netns) but seccomp-blocks inet ->
#       proves seccomp blocks families independently of --unshare-net; unix allowed.
#   - probe-net:          `network=true`, no filter -> inet sockets create fine.
# Probed by running the socketFamily node probe under each profile:
# `<probe>-shell -c 'node ${probe} <fam>'` inherits that profile's seccomp (skip=true ->
# no re-wrap). EACCES is the filter's signature. -shell, not -debug: same launcher and
# sandbox without strace, which is pathologically slow under aarch64 TCG.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  probeTools = import ../probe-tools { inherit pkgs; };
  p = probes.socketFamily;
  # Run the payload under a profile's seccomp via that probe's -shell. Everything is an
  # absolute store path: the probes are not installed on the machine under test, and a
  # launcher's keepEnv may drop PATH so `node` wouldn't resolve by name inside anyway.
  # Store paths resolve in the sandbox because the host root is ro-bound.
  under = tool: fam: "${probeTools.shell tool} -c '${pkgs.nodejs}/bin/node ${p} ${fam}'";
in
{
  testScript = ''
    # 1) default no-net (probe-default): inet/inet6 blocked by autoBlock, unix allowed.
    assert "ERR:EACCES" in run_user("${under "probe-default" "udp4"}"), "probe-default udp4 should be EACCES (seccomp)"
    assert "ERR:EACCES" in run_user("${under "probe-default" "udp6"}"), "probe-default udp6 should be EACCES (seccomp)"
    assert "OK" == run_user("${under "probe-default" "unix"}").strip(), "probe-default should allow AF_UNIX"

    # 2) locked-down no-net (probe-unix-blocked): explicit AF_UNIX block on top of autoBlock.
    assert "ERR:EACCES" in run_user("${under "probe-unix-blocked" "udp4"}"), "probe-unix-blocked udp4 should be EACCES"
    assert "ERR:EACCES" in run_user("${under "probe-unix-blocked" "unix"}"), "probe-unix-blocked should also block AF_UNIX"

    # 3) probe-inet-blocked: network=true (shares netns) but seccomp-blocks inet; unix allowed.
    assert "ERR:EACCES" in run_user("${under "probe-inet-blocked" "udp4"}"), "probe-inet-blocked udp4 should be EACCES (seccomp, not netns)"
    assert "ERR:EACCES" in run_user("${under "probe-inet-blocked" "udp6"}"), "probe-inet-blocked udp6 should be EACCES"
    assert "OK" == run_user("${under "probe-inet-blocked" "unix"}").strip(), "probe-inet-blocked should allow AF_UNIX"

    # 4) net profile (probe-net): no seccomp filter -> inet socket creates (not EACCES).
    assert "EACCES" not in run_user("${under "probe-net" "udp4"}"), "probe-net must not seccomp-block AF_INET"
  '';
}
