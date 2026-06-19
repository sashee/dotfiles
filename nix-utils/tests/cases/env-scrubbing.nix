# Case: the launcher's environment scrubbing (env -i + keepEnv re-add + setEnv inject).
# A tool with a non-null keepEnv starts from an empty env and re-adds only kept vars, so
# a host secret NOT in keepEnv must be ABSENT inside its sandbox; a tool with keepEnv=null
# passes the parent env through. The security crux: host credentials don't leak into an
# agent (claude) that doesn't list them, but do reach the tool (aws) that does.
# -debug reuses the same launcher (bin.override), so its env handling matches the real tool.
{ pkgs }:
let
  printenv = "${pkgs.coreutils}/bin/printenv";
in
{
  testScript = ''
    def names(out):
        return {l.split("=", 1)[0] for l in out.splitlines() if "=" in l}

    # 1) Scrubbing tool (claude, keepEnv without arbitrary vars): host secret dropped,
    # keepEnv + always-added vars survive.
    env_c = run_user("NIXUTILS_SECRET=leaked-do-not-pass claude-debug -c '${printenv}'")
    assert "leaked-do-not-pass" not in env_c, "claude must scrub NIXUTILS_SECRET (not in its keepEnv)"
    for v in ["HOME", "PATH", "XDG_RUNTIME_DIR", "__NIX_UTILS_SKIP_SANDBOX"]:
        assert v in names(env_c), f"claude should keep {v} (keepEnv / always-added); names={sorted(names(env_c))}"

    # 2) Non-scrubbing tool (node, keepEnv=null): the host env passes through unchanged.
    env_n = run_user("NIXUTILS_SECRET=leaked-do-not-pass node-debug -c '${printenv}'")
    assert "leaked-do-not-pass" in env_n, "node (keepEnv=null) should pass the host env through"

    # 3) setEnv injection: opencode injects OPENCODE_CONFIG.
    assert "OPENCODE_CONFIG" in names(run_user("opencode-debug -c '${printenv}'")), (
        "opencode-debug should inject its setEnv OPENCODE_CONFIG"
    )

    # 4) Secret cross-check: a host AWS credential is dropped by an agent that doesn't list
    # it (claude) but reaches the tool that does (aws keepEnv includes AWS_ACCESS_KEY_ID).
    assert "AKIAFAKELEAKTEST" not in run_user("AWS_ACCESS_KEY_ID=AKIAFAKELEAKTEST claude-debug -c '${printenv}'"), (
        "claude must NOT leak the host AWS_ACCESS_KEY_ID into the agent sandbox"
    )
    assert "AKIAFAKELEAKTEST" in run_user("AWS_ACCESS_KEY_ID=AKIAFAKELEAKTEST aws-debug -c '${printenv}'"), (
        "aws keepEnv must pass AWS_ACCESS_KEY_ID through to the tool that needs it"
    )
  '';
}
