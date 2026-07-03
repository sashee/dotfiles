# Case: the sandboxed `git` is hardened and confined.
#   - command-line config disables the attacker-reachable exec knobs (hooksPath,
#     fsmonitor, …) — git/default.nix.
#   - a malicious repo-local hook does not execute on the host.
#   - a default identity is baked in (GIT_CONFIG_GLOBAL), so a bare commit works
#     with no ~/.gitconfig, yet a repo-local user.email still overrides it.
#   - git is confined to the git root: files outside the repo (incl. ~/.gitconfig)
#     are not readable.
#   - ~/.ssh/known_hosts is pre-created on the host (mkdir + type=file) and bound
#     rw, so a first host-key acceptance persists instead of vanishing with the
#     tmpfs /home each run.
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

    # Baked-in identity: a bare commit (no -c, no ~/.gitconfig) uses the default.
    run_user("cd ~/proj && git commit -q --allow-empty -m baked")
    ae = run_user("cd ~/proj && git log -1 --format=%ae")
    assert ae.strip() == "tamas.sallai@advancedweb.hu", f"author email = {ae!r}"

    # ...but a repo-local user.email still overrides the baked default.
    run_user("cd ~/proj && git config --local user.email repo@local")
    run_user("cd ~/proj && git commit -q --allow-empty -m override")
    ae = run_user("cd ~/proj && git log -1 --format=%ae")
    assert ae.strip() == "repo@local", f"author email = {ae!r}"
    run_user("cd ~/proj && git config --local --unset user.email")

    # Confinement: files outside the repo root are not readable, incl. ~/.gitconfig.
    run_user(r"printf '[user]\n\temail = t@e\n' > ~/.gitconfig")
    run_user(r"printf '[user]\n\temail = x@y\n' > ~/secret-outside.txt")
    run_user("cd ~/proj && git config --file $HOME/.gitconfig --list", succeed=False)
    run_user("cd ~/proj && git config --file $HOME/secret-outside.txt --list", succeed=False)

    # Containment: git filters aren't disabled (no global off-switch), but run
    # inside the sandbox confined to the repo root — they can write in the repo but
    # not escape to $HOME outside it.
    run_user(r"cd ~/proj && printf '* filter=evil\n' > .gitattributes")
    run_user("cd ~/proj && git config --local filter.evil.clean ${filterClean}")
    run_user("cd ~/proj && echo data > tracked.txt && git -c user.email=t@e -c user.name=t add tracked.txt")
    run_user("test -e ~/proj/filter-ran")               # the filter DID run (inside the repo root)
    run_user("test -e ~/pwned-filter", succeed=False)   # but could not write outside it

    # SSH host-key persistence: on a fresh machine ~/.ssh/known_hosts doesn't exist,
    # so the wrapper pre-creates it on the host (mkdir + type=file) — any git run
    # triggers the host-side pre-create at runner startup.
    run_user("rm -rf ~/.ssh")
    run_user("cd ~/proj && git --version")
    run_user("test -f ~/.ssh/known_hosts")              # pre-created on the host, as a file

    # ...and it's bound rw, so an append from inside the sandbox persists on the host
    # (this is what makes a first-time host-key acceptance stick).
    run_user("cd ~/proj && git-debug -c 'echo example.com ssh-ed25519 AAAATESTKEY >> ~/.ssh/known_hosts'")
    kh = run_user("cat ~/.ssh/known_hosts")
    assert "AAAATESTKEY" in kh, f"a write to the rw-bound ~/.ssh/known_hosts must persist on the host; got {kh!r}"

    run_user("rm -rf ~/proj ~/secret-outside.txt ~/pwned ~/pwned-filter ~/.gitconfig ~/.ssh")
  '';
}
