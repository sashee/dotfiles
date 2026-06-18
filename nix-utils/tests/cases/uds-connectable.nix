# Case: a sandboxed tool must not be able to connect() to any unix-domain socket
# outside the global allowlist (consts.allowedSockets). `protectedPaths` is a
# denylist, so a new program/service can add a socket it doesn't cover; this flips
# it to an allowlist — any reachable socket not explicitly allowed fails the build,
# so it gets reviewed (block it via protectedPaths, or add it to allowedSockets).
#
# Subset, not equality: the allowlist is one global list (consts.nix), valid across
# machines. A given machine may not have every allowed socket present — that's fine
# — but it must never expose one that isn't allowed.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  consts = import ../../consts.nix;
in
{
  testScript = ''
    allowed = set(${builtins.toJSON consts.allowedSockets})
    actual = set(
        run_user("node ${probes.auditConnectable} /run /tmp /dev/shm /var").split()
    )
    extra = sorted(actual - allowed)
    assert not extra, (
        "sandboxed tool can connect() to unix sockets not in consts.allowedSockets "
        f"(block them in protectedPaths or allow them): {extra}"
    )
  '';
}
