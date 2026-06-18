# Case: /tmp is a per-sandbox tmpfs (--tmpfs /tmp), so host /tmp is masked and a
# tool's /tmp writes are ephemeral — no cross-tool /tmp leakage, no host /tmp
# tampering.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    # Host /tmp is invisible inside the sandbox (masked by the tmpfs).
    machine.succeed("echo HOSTTMP > /tmp/nsr-host-tmp")
    out = run_user("node ${probes.readFile} /tmp/nsr-host-tmp 2>&1 || true")
    assert "HOSTTMP" not in out, f"host /tmp leaked into the sandbox: {out!r}"

    # A tool's /tmp write lands in the ephemeral tmpfs and never reaches host /tmp.
    run_user("node ${probes.writeFile} /tmp/nsr-inside")
    run_user("test -e /tmp/nsr-inside", succeed=False)

    machine.succeed("rm -f /tmp/nsr-host-tmp")
  '';
}
