# Per-program case: the login shells keep their tools on PATH inside the sandbox. On
# the host the tools are reached through a symlink under home
# (~/dotfiles/nix-utils/result/bin), which the sandbox's --tmpfs /home hides, so a shell
# launched outside home inherited a dead PATH entry and lost every tool. The zshrc
# prepends a store-path env of the shell's programs instead (zsh/default.nix prgs_env).
#
# Recreates that layout: ~/result -> a store path holding the tools, and a PATH whose
# ONLY route to them is ~/result/bin (coreutils has none of them). Interactive (-i)
# because zsh reads the zshrc only for interactive shells. The store path is the profile
# the login shell finds zsh-nonet in (the same lookup `present` guards on), not the
# hardcoded /run/current-system/sw: a machine may install the tools per-user.
{ pkgs }:
let
  coreutils = pkgs.coreutils;
in
{
  testScript = ''
    if not present("zsh-nonet") or not present("git"):
        skip_absent("zsh-nonet / git")
    else:
        run_user('rm -rf ~/work ~/result && mkdir -p ~/work && ln -s "$(readlink -f "$(dirname "$(command -v zsh-nonet)")/..")" ~/result')

        for shell in ["zsh", "zsh-nonet"]:
            out = run_user(
                "cd ~/work && PATH=$HOME/result/bin:${coreutils}/bin " + shell + " -ic '"
                "test -e ~/result/bin; echo HOME_ENTRY_RC=$?; "
                "echo GIT_PATH=$(whence -p git); "
                "git --version; echo GIT_RC=$?"
                "' 2>&1"
            )
            # Precondition: the inherited home entry must really be dead inside, or the
            # rest proves nothing.
            assert "HOME_ENTRY_RC=0" not in out, (
                f"{shell}: ~/result/bin must be hidden by --tmpfs /home; got {out!r}"
            )
            git_path = next(
                (l.split("=", 1)[1] for l in out.splitlines() if l.startswith("GIT_PATH=")), ""
            ).strip()
            assert git_path.startswith("/nix/store/"), (
                f"{shell}: git must resolve through a store path, not the hidden home entry; got {out!r}"
            )
            assert "GIT_RC=0" in out, f"{shell}: git must run from inside the shell; got {out!r}"

        run_user("rm -rf ~/work ~/result")
  '';
}
