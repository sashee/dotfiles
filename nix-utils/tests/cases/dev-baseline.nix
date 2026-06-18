# Case: the hardcoded consts.fakeDevEntries (the /dev nodes the runner keeps for
# dev-allowlist tools, instead of probing bwrap on every launch) still matches what
# `bwrap --dev /dev` actually creates for the pinned bubblewrap. Guards against a
# future bubblewrap changing its --dev population.
{ pkgs }:
let
  consts = import ../../consts.nix;
in
{
  testScript = ''
    expected = set(${builtins.toJSON consts.fakeDevEntries})
    out = run_user("${pkgs.bubblewrap}/bin/bwrap --ro-bind / / --dev /dev -- ${pkgs.coreutils}/bin/ls -1A /dev")
    actual = set(out.split())
    assert actual == expected, (
        f"consts.fakeDevEntries drifted from `bwrap --dev`: "
        f"missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
    )
  '';
}
