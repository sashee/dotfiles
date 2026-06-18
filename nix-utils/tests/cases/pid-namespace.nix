# Case: the sandbox runs in its own PID namespace (`--unshare-pid`) with a fresh
# `/proc`, so host processes are invisible inside it. The host's PID 1 is systemd;
# inside the sandbox it isn't, and only a handful of processes are visible.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    host = machine.succeed("cat /proc/*/comm").split()
    assert "systemd" in host, "sanity: the host should be running systemd"

    inside = run_user("node ${probes.procComms}").split()
    assert "systemd" not in inside, f"host processes leaked into the sandbox PID ns: {inside!r}"
    assert len(inside) < 15, f"unexpectedly many processes visible inside the sandbox: {inside!r}"
  '';
}
