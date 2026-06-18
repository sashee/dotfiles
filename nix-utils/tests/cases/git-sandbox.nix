# Case: the sandboxed `git` is hardened and confined.
#   - command-line config disables the attacker-reachable exec knobs (hooksPath,
#     fsmonitor, …) — git/default.nix.
#   - a malicious repo-local hook does not execute on the host.
#   - git is confined to the git root: it reads opted-in ~/.gitconfig but not an
#     arbitrary file outside the repo.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  # A repo-local `clean` filter: writes inside the repo (allowed) and tries to
  # escape to $HOME (must be contained). `cat` passes the content through.
  filterClean = pkgs.writeShellScript "nsr-evil-clean" ''
    touch filter-ran
    touch "$HOME/pwned-filter"
    cat
  '';
in
{
  testScript = ''
    run_user("rm -rf ~/proj ~/secret-outside.txt ~/pwned ~/.gitconfig")
    run_user("mkdir -p ~/proj && cd ~/proj && git init -q")

    # Hardening: the exec knobs are pinned off via command-line config.
    hp = run_user("cd ~/proj && git config --get core.hooksPath")
    assert hp.strip() == "/dev/null", f"core.hooksPath = {hp!r}"
    fm = run_user("cd ~/proj && git config --get core.fsmonitor")
    assert fm.strip() == "false", f"core.fsmonitor = {fm!r}"

    # A malicious pre-commit hook must NOT run (hooksPath -> /dev/null).
    run_user(r"printf '#!/bin/sh\ntouch $HOME/pwned\n' > ~/proj/.git/hooks/pre-commit")
    run_user("chmod +x ~/proj/.git/hooks/pre-commit")
    run_user("cd ~/proj && git -c user.email=t@e -c user.name=t commit -q --allow-empty -m x")
    run_user("test -e ~/pwned", succeed=False)  # the hook did not fire on the host

    # Confinement: opted-in ~/.gitconfig is readable, an outside file is not.
    run_user(r"printf '[user]\n\temail = t@e\n' > ~/.gitconfig")
    run_user(r"printf '[user]\n\temail = x@y\n' > ~/secret-outside.txt")
    run_user("cd ~/proj && git config --file $HOME/.gitconfig --list")
    run_user("cd ~/proj && git config --file $HOME/secret-outside.txt --list", succeed=False)

    # Containment: git filters aren't disabled (no global off-switch), but run
    # inside the sandbox confined to the repo root — they can write in the repo but
    # not escape to $HOME outside it.
    run_user(r"cd ~/proj && printf '* filter=evil\n' > .gitattributes")
    run_user("cd ~/proj && git config --local filter.evil.clean ${filterClean}")
    run_user("cd ~/proj && echo data > tracked.txt && git -c user.email=t@e -c user.name=t add tracked.txt")
    run_user("test -e ~/proj/filter-ran")               # the filter DID run (inside the repo root)
    run_user("test -e ~/pwned-filter", succeed=False)   # but could not write outside it

    run_user("rm -rf ~/proj ~/secret-outside.txt ~/pwned ~/pwned-filter ~/.gitconfig")
  '';
}
