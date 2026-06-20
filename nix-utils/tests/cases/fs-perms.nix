# Case: per-path filesystem permission enforcement (rw vs ro), beyond read-only-root's
# `/` check. Uses nvim, which binds $HOME/.cache/nvim rw (mkdir) and ro-binds a config
# file to $HOME/eslint.config.js via the `files` mechanism.
#   - rw  : a write inside persists to the real host dir (the bind is the host path).
#   - files ro-bind: the dest is readable but writes fail (EROFS/EACCES) and don't change it.
{ pkgs }:
let
  coreutils = pkgs.coreutils;
in
{
  testScript = ''
    # Run from a neutral cwd so restrict_to_current_folder binds ~/work (not all of $HOME):
    # the rw-persist then genuinely exercises the ~/.cache/nvim opt-in bind, and the
    # read-back stays user-agnostic (~ expands in the user's login shell).
    run_user("rm -rf ~/work && mkdir -p ~/work")

    # rw opt-in: write inside the sandbox, verify it lands on the host.
    run_user("cd ~/work && nvim-debug -c '${coreutils}/bin/install -d ~/.cache/nvim && ${coreutils}/bin/echo hi > ~/.cache/nvim/probe'")
    host = run_user("cat ~/.cache/nvim/probe").strip()
    assert host == "hi", f"writes to the rw-bound ~/.cache/nvim must persist on the host; got {host!r}"

    # files ro-bind: present + readable...
    content = run_user("cd ~/work && nvim-debug -c '${coreutils}/bin/cat ~/eslint.config.js'")
    assert content.strip(), "the files ro-bind ~/eslint.config.js must be present and readable"
    # ...but read-only: a write must fail (RC != 0) and leave the content unchanged.
    rc = run_user("cd ~/work && nvim-debug -c '${coreutils}/bin/echo x > ~/eslint.config.js; echo RC=$?' 2>&1")
    assert "RC=0" not in rc, f"writing to the ro files-bind must fail (read-only); got {rc!r}"
    after = run_user("cd ~/work && nvim-debug -c '${coreutils}/bin/cat ~/eslint.config.js'")
    assert after == content, "the ro files-bind content must be unchanged after a failed write"

    run_user("rm -rf ~/work")
  '';
}
