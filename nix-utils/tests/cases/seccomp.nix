# Case: the seccomp socket-family filter. The runner fails socket(family) with
# EACCES for blocked families. Three profiles (see _wrapper/default.nix afMap +
# autoBlock, and the tools' explicit seccomp.block):
#   - default no-net (node-nonet): inet/inet6 blocked, unix allowed.
#   - locked-down no-net (sqlite3): autoBlock + explicit AF_UNIX block -> unix also
#     refused.
#   - keepassxc: network=true (shares the netns) but seccomp-blocks inet -> proves
#     seccomp blocks inet independently of --unshare-net; unix stays allowed.
#   - net tool (node): no filter -> inet sockets create fine.
# Probed by running the socketFamily node probe under each tool's filter:
# `<tool>-debug -c 'node ${probe} <fam>'` inherits that tool's seccomp (skip=true ->
# no re-wrap). EACCES is the filter's signature. node is the always-net reference.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  p = probes.socketFamily;
  # Run the probe under a tool's seccomp via its -debug shell. Use node's absolute
  # store path: a tool's keepEnv may drop PATH, so `node` isn't resolvable by name
  # inside; a store path also resolves in the sandbox (host root is ro-bound) without
  # depending on the machine under test having node in its system profile.
  # The wrapper sees skip=true and runs node un-rewrapped under the tool's seccomp.
  under = tool: fam: "${tool}-debug -c '${pkgs.nodejs}/bin/node ${p} ${fam}'";
in
{
  testScript = ''
    # 1) default no-net (node-nonet): inet/inet6 blocked, unix allowed.
    assert "ERR:EACCES" in run_user("node-nonet ${p} udp4"), "node-nonet udp4 should be EACCES (seccomp)"
    assert "ERR:EACCES" in run_user("node-nonet ${p} udp6"), "node-nonet udp6 should be EACCES (seccomp)"
    assert "OK" == run_user("node-nonet ${p} unix").strip(), "node-nonet should allow AF_UNIX"

    # 2) locked-down no-net (sqlite3): explicit AF_UNIX block on top of autoBlock.
    assert "ERR:EACCES" in run_user("${under "sqlite3" "udp4"}"), "sqlite3 udp4 should be EACCES"
    assert "ERR:EACCES" in run_user("${under "sqlite3" "unix"}"), "sqlite3 should also block AF_UNIX"

    # 3) keepassxc: network=true (shares netns) but seccomp-blocks inet; unix allowed.
    assert "ERR:EACCES" in run_user("${under "keepassxc" "udp4"}"), "keepassxc udp4 should be EACCES (seccomp, not netns)"
    assert "ERR:EACCES" in run_user("${under "keepassxc" "udp6"}"), "keepassxc udp6 should be EACCES"
    assert "OK" == run_user("${under "keepassxc" "unix"}").strip(), "keepassxc should allow AF_UNIX"

    # 4) net tool (node): no seccomp filter -> inet socket creates (not EACCES).
    assert "EACCES" not in run_user("node ${p} udp4"), "node (net) must not seccomp-block AF_INET"
  '';
}
