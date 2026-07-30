# Machinery case: the launcher's environment scrubbing (env -i + keepEnv re-add + setEnv
# inject). A launcher with a non-null keepEnv starts from an empty env and re-adds only the
# kept vars, so a host secret NOT in keepEnv must be ABSENT inside its sandbox; a launcher
# with keepEnv=null passes the parent env through. Both sides are synthetic probes (see
# ../probe-tools) — the scrubbing is what's under test, and pinning it to a probe means it
# stays asserted on a machine that installs no agent at all. What a REAL agent's keepEnv
# contains is its own business: see program-claude.nix for that.
# -shell reuses the same launcher (bin.override), so its env handling matches the profile.
{ pkgs }:
let
  probeTools = import ../probe-tools { inherit pkgs; };
  printenv = "${pkgs.coreutils}/bin/printenv";
  # Store paths: the probes are not installed on the machine under test.
  scrub = probeTools.shell "probe-scrub";
  passthru = probeTools.shell "probe-passthru";
in
{
  testScript = ''
    def names(out):
        return {l.split("=", 1)[0] for l in out.splitlines() if "=" in l}

    # 1) Scrubbing launcher (keepEnv without arbitrary vars): host secret dropped,
    # keepEnv + always-added vars survive.
    env_s = run_user("NIXUTILS_SECRET=leaked-do-not-pass ${scrub} -c '${printenv}'")
    assert "leaked-do-not-pass" not in env_s, "a scrubbing launcher must drop NIXUTILS_SECRET (not in its keepEnv)"
    for v in ["HOME", "PATH", "XDG_RUNTIME_DIR", "__NIX_UTILS_SKIP_SANDBOX"]:
        assert v in names(env_s), f"a scrubbing launcher should keep {v} (keepEnv / always-added); names={sorted(names(env_s))}"

    # 2) Non-scrubbing launcher (keepEnv=null): the host env passes through unchanged.
    env_p = run_user("NIXUTILS_SECRET=leaked-do-not-pass ${passthru} -c '${printenv}'")
    assert "leaked-do-not-pass" in env_p, "keepEnv=null should pass the host env through"

    # 3) setEnv injection: probe-scrub declares PROBE_SETENV.
    assert names(env_s) >= {"PROBE_SETENV"}, (
        f"probe-scrub should inject its setEnv PROBE_SETENV; names={sorted(names(env_s))}"
    )

    # 4) The re-add is SELECTIVE, not all-or-nothing: with two host vars set, the one
    # named in keepEnv (PROBE_KEEP — this is how aws gets AWS_ACCESS_KEY_ID) survives
    # while the one that isn't named is dropped, in the very same launch.
    both = run_user(
        "PROBE_KEEP=kept-value NIXUTILS_SECRET=leaked-do-not-pass ${scrub} -c '${printenv}'"
    )
    assert "kept-value" in both, f"a var listed in keepEnv must reach the sandbox; got names={sorted(names(both))}"
    assert "leaked-do-not-pass" not in both, "a var NOT listed in keepEnv must not reach the sandbox"
  '';
}
