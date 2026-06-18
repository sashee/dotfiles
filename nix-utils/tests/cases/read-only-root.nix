# Case: the root filesystem is mounted read-only (`--ro-bind / /`), so a tool
# cannot write outside its explicitly granted rw paths (e.g. into /etc).
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    # Writing into /etc fails (read-only root).
    run_user("node ${probes.writeFile} /etc/nsr-probe", succeed=False)
    machine.succeed("test ! -e /etc/nsr-probe")
  '';
}
