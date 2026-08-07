# Per-program case: the login shells' home scoping. zsh folds every zshProgram's
# sandbox_restrictions.fs into its own (zsh/default.nix), which is how a tool launched from
# the shell keeps working through nesting — but a program that claims a BARE ROOT for itself
# must not widen the shell. libreoffice takes all of $HOME rw (it must open documents
# anywhere); merging that re-exposed the entire real home rw and made
# restrict_to_current_folder a no-op, so `ls ~` in zsh-nonet listed every host home entry,
# ~/.ssh keys included. consts.unmergeableFsPaths now drops such keys from the merge.
#
# What must hold, for BOTH shells (the filter is in the shared merge, and the net/nonet
# variants differ only in network — a regression would hit both):
#   - home outside the launch folder is not visible at all (the base --tmpfs /home stands)
#   - the launch folder is still rw and persists to the host (confinement, not lockout)
#   - an opt-in home SUBPATH still merges through the filter (only bare roots are dropped)
{ pkgs }:
let
  coreutils = pkgs.coreutils;
in
{
  testScript = ''
    if not present("zsh-nonet-shell"):
        skip_absent("zsh")
    else:
        # Launch from a neutral non-repo dir: resolve_restrict_path finds no .git above it
        # and falls back to the cwd, so the writable window is exactly ~/work. Launching
        # from ~ would bind all of $HOME and prove nothing (same reasoning as fs-perms).
        run_user("rm -rf ~/work && mkdir -p ~/work ~/.cache && echo tell-no-one > ~/outside-probe")

        # -shell (not -debug): bash in the real sandbox without strace, which is
        # pathologically slow under aarch64 TCG. Absolute store paths because the
        # sandboxed PATH is the launcher's, not the machine's system profile.
        for shell in ["zsh-shell", "zsh-nonet-shell"]:
            out = run_user(
                "cd ~/work && " + shell + " -c '"
                "${coreutils}/bin/cat ~/outside-probe; echo CAT_RC=$?; "
                "${coreutils}/bin/test -e ~/outside-probe; echo EXISTS_RC=$?"
                "' 2>&1"
            )
            assert "tell-no-one" not in out, (
                f"{shell} launched in ~/work must not be able to read $HOME outside it "
                f"(a bare $HOME merged into the shell's fs undoes --tmpfs /home); got {out!r}"
            )
            assert "CAT_RC=0" not in out, f"{shell}: reading ~/outside-probe must fail; got {out!r}"
            assert "EXISTS_RC=0" not in out, (
                f"{shell}: ~/outside-probe must not even exist inside the sandbox; got {out!r}"
            )

            # The launch folder is the writable window: a write there lands on the host.
            run_user("cd ~/work && " + shell + " -c '${coreutils}/bin/echo hi > ~/work/probe-" + shell + "'")
            landed = run_user("cat ~/work/probe-" + shell).strip()
            assert landed == "hi", (
                f"{shell} must keep the launch folder rw (restrict_to_current_folder); got {landed!r}"
            )

            # Opt-in subpaths must survive the filter (it drops bare roots only).
            run_user("cd ~/work && " + shell + " -c '${coreutils}/bin/echo hi > ~/.cache/zsh-scoping-probe'")
            cached = run_user("cat ~/.cache/zsh-scoping-probe").strip()
            assert cached == "hi", (
                f"{shell} must still have the merged ~/.cache opt-in bind rw; got {cached!r}"
            )
            run_user("rm -f ~/.cache/zsh-scoping-probe")

        run_user("rm -rf ~/work ~/outside-probe")
  '';
}
