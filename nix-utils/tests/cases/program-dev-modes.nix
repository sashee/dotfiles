# Per-program case: which real programs get a private /dev and which the live host /dev.
# zellij/tmux are the outermost layer and take the live host /dev (dev = { live = ...; })
# so devices plugged in later reach new panes; everything that runs your code inside them
# — the shells and the agents — gets bwrap's private /dev, so it can't open your other
# terminals (/dev/pts) or the host's /dev/shm. The modes themselves are covered by
# dev-allowlist.nix; this pins which program uses which (e.g. `live` creeping into zsh's
# exported restrictions would hand every pane the host's terminals again).
{ pkgs }:
let
  coreutils = pkgs.coreutils;
in
{
  testScript = ''
    host_pts = machine.succeed("${coreutils}/bin/stat -c %d /dev/pts").strip()
    for shell, shares_host in [
        ("zsh-shell", False),
        ("zsh-nonet-shell", False),
        ("claude-shell", False),
        ("opencode-shell", False),
        ("zellij-shell", True),
        ("tmux-shell", True),
    ]:
        if not present(shell):
            skip_absent(shell)
            continue
        pts = run_user(shell + " -c '${coreutils}/bin/stat -c %d /dev/pts'").strip().splitlines()[-1]
        assert (pts == host_pts) == shares_host, (
            f"{shell}: /dev/pts should be {'the host' if shares_host else 'a private'} instance; "
            f"host {host_pts}, sandbox {pts}"
        )
  '';
}
