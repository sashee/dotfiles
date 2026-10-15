# Per-program case: which programs may reach the nix daemon. The daemon builds
# fixed-output derivations WITH network access, so a sandbox that can connect to its
# socket can fetch/exfiltrate through it even under --unshare-net. The socket dir is in
# consts.protectedPaths; zsh, claude and opencode opt back in (all network = true).
#
# What must hold:
#   - zsh reaches the daemon (nix-shell / nix-build from the shell).
#   - zsh-nonet does NOT: it shares zsh's merged fs, so the opt-in must be stripped there
#     (a regression in that strip is exactly the bypass this guards against).
#   - claude / opencode reach it (agents are told to use nix for tools).
# Tools without an opt-in are covered by uds-connectable.nix.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  consts = import ../../consts.nix;
  node = "${pkgs.nodejs}/bin/node";
  socketDir = consts.nixDaemonSocketDir;
in
{
  testScript = ''
    # -shell: bash in the tool's real sandbox; node by store path so the probe runs in
    # that sandbox rather than in the nested `node` wrapper's.
    for shell, expected in [
        ("zsh-shell", True),
        ("zsh-nonet-shell", False),
        ("claude-shell", True),
        ("opencode-shell", True),
    ]:
        if not present(shell):
            skip_absent(shell)
            continue
        out = run_user(shell + " -c '${node} ${probes.auditConnectable} ${socketDir}'")
        reached = "${socketDir}/socket" in out
        assert reached == expected, (
            f"{shell}: nix daemon socket reachable={reached}, expected {expected}; got {out!r}"
        )
  '';
}
