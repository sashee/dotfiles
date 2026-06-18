# Case: node's cache access is scoped to the specific subdirs it opts into
# (~/.cache/pnpm, …) rather than all of ~/.cache, so untrusted package scripts
# can't poison caches other tools later trust. A write to an opted-in dir persists
# on the host; a write to a non-opted dir lands in the ephemeral /home tmpfs and
# never reaches the host.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    # Run from a neutral subdir: with cwd = $HOME, restrict_to_current_folder would
    # bind all of /home rw and every write would persist. From ~/work, home stays a
    # tmpfs and only the opted-in cache dirs are bound.
    run_user("rm -rf ~/.cache/pnpm/nsr-probe ~/.cache/evil ~/work")
    run_user("mkdir -p ~/work")

    # Opted-in cache dir: the write persists on the host.
    run_user("cd ~/work && node ${probes.writeFile} $HOME/.cache/pnpm/nsr-probe")
    run_user("test -e ~/.cache/pnpm/nsr-probe")

    # Non-opted dir: the write "succeeds" in the tmpfs but is absent on the host.
    run_user("cd ~/work && node ${probes.writeFile} $HOME/.cache/evil/nsr-probe")
    run_user("test -e ~/.cache/evil/nsr-probe", succeed=False)

    run_user("rm -rf ~/.cache/pnpm/nsr-probe ~/.cache/evil ~/work")
  '';
}
