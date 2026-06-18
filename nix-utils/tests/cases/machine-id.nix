# Case: each sandbox gets a fresh random /etc/machine-id (32 hex chars), different
# from the host's and from other sandboxes — so tools can't fingerprint the machine
# or link activity across the host/sandbox boundary.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    host = machine.succeed("cat /etc/machine-id").strip()

    a = run_user("node ${probes.printMachineId}").strip()
    b = run_user("node ${probes.printMachineId}").strip()

    assert a != host, f"machine-id not faked: {a} == host"
    assert b != host, f"machine-id not faked: {b} == host"
    assert a != b, f"machine-id not random per sandbox: {a} == {b}"
    assert len(a) == 32, f"machine-id wrong length: {a!r}"
    int(a, 16)  # must be valid lowercase hex (raises ValueError otherwise)
    assert a == a.lower(), f"machine-id must be lowercase hex: {a!r}"
  '';
}
