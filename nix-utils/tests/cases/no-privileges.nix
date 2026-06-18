# Case: a sandboxed tool has no privileges and can't escalate. bwrap maps the
# process to uid 1000 and drops all capabilities, so even inside the user namespace
# it has no effective caps and cannot setuid to root (root is unmapped).
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    import json
    r = json.loads(run_user("node ${probes.privCheck}"))
    assert r["setuid"].startswith("denied"), f"setuid(0) must fail in the sandbox: {r}"
    assert r["capeff"] == "0000000000000000", f"sandbox must have no effective capabilities: {r}"
    assert r["uid"].split()[:2] == ["1000", "1000"], f"unexpected uid (want 1000): {r}"
  '';
}
