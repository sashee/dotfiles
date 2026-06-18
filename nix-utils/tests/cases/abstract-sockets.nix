# Case: abstract-namespace unix sockets. They have no filesystem path, so the
# filesystem-based protections (protectedPaths, --ro-bind / /) don't touch them —
# they're isolated only by the network namespace. So:
#   A. a network=false tool (--unshare-net, own netns) cannot reach a host abstract
#      socket, while a network=true tool (shares the host netns) can. This pins down
#      that --unshare-net is what isolates the abstract namespace.
#   B. nothing a sandboxed tool can reach is a *listening* abstract socket outside
#      the global allowlist (consts.allowedAbstractSockets) — guards against a future
#      config exposing one (e.g. an X server's @/tmp/.X11-unix/X0).
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  consts = import ../../consts.nix;
in
{
  testScript = ''
    # --- A: --unshare-net isolates the abstract namespace ---
    # Plant a listener in the HOST netns (skip-sandbox node = unsandboxed).
    run_user("(__NIX_UTILS_SKIP_SANDBOX=true node ${probes.abstractServer} nsr-abs >/tmp/nsr-abs.log 2>&1 & echo $! > /tmp/nsr-abs.pid)")
    machine.wait_until_succeeds("grep -q '@nsr-abs' /proc/net/unix")

    # network=true shares the host netns -> reaches the abstract socket
    out = run_user("node ${probes.abstractConnect} nsr-abs")
    assert "connected" in out, f"net tool should reach the host abstract socket: {out!r}"

    # network=false has its own netns -> cannot
    run_user("node-nonet ${probes.abstractConnect} nsr-abs", succeed=False)

    run_user("kill $(cat /tmp/nsr-abs.pid) 2>/dev/null || true")
    run_user("rm -f /tmp/nsr-abs.pid /tmp/nsr-abs.log")
    machine.wait_until_succeeds("! grep -q '@nsr-abs' /proc/net/unix")

    # --- B: no reachable abstract listener outside the allowlist ---
    allowed = set(${builtins.toJSON consts.allowedAbstractSockets})
    listeners = set(
        run_user("node ${probes.auditAbstractListeners}").split()
    )
    extra = sorted(listeners - allowed)
    assert not extra, (
        "sandboxed tool can reach abstract-namespace listeners not in "
        f"consts.allowedAbstractSockets (block via netns or allow): {extra}"
    )
  '';
}
