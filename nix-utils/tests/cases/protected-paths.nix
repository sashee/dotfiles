# Case: paths blocked by default in consts.nix are unreadable from a tool that
# didn't opt into them. Plant a sentinel at each, then confirm `node` can't read
# its content. The skip-sandbox control proves the sandbox is what blocks them.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    # Plant sentinels (tester-owned via run_user, root-owned via machine).
    run_user("mkdir -p ~/.config && echo CONFIGSECRET > ~/.config/nsr-secret")
    run_user("mkdir -p $XDG_RUNTIME_DIR/gnupg && echo GPGSECRET > $XDG_RUNTIME_DIR/gnupg/sentinel")
    machine.succeed("mkdir -p /var/log/journal && echo JOURNALSECRET > /var/log/journal/nsr-marker")
    machine.succeed("printf DOCKERSECRET > /run/docker.sock")

    # For each blocked path, node must not see the planted content. (2>&1||true:
    # a file-block maps to /dev/null so the read *succeeds* but is empty, while a
    # dir-block / missing file makes the read fail — both must lack the secret.)
    for path, needle in [
        ("$HOME/.config/nsr-secret", "CONFIGSECRET"),
        ("$XDG_RUNTIME_DIR/gnupg/sentinel", "GPGSECRET"),
        ("/var/log/journal/nsr-marker", "JOURNALSECRET"),
        ("/run/docker.sock", "DOCKERSECRET"),
    ]:
        out = run_user(f"node ${probes.readFile} {path} 2>&1 || true")
        assert needle not in out, f"{path} leaked into the sandbox: {out!r}"

    # The systemd user-manager socket dir is masked empty (StartTransientUnit guard).
    machine.succeed("ls -A /run/user/1000/systemd")  # sanity: non-empty on the host
    # No 2>&1 here: listDir succeeds, so stdout is just the JSON (node's non-quiet
    # "Restricting to folder" line goes to stderr, which we don't capture).
    out = run_user("node ${probes.listDir} $XDG_RUNTIME_DIR/systemd")
    assert out.strip() == "[]", f"systemd dir not empty inside sandbox: {out!r}"

    # Control: with the sandbox bypassed, the same read DOES return the secret.
    out = run_user("__NIX_UTILS_SKIP_SANDBOX=true node ${probes.readFile} $HOME/.config/nsr-secret 2>&1 || true")
    assert "CONFIGSECRET" in out, f"skip-sandbox should bypass and read the secret, got: {out!r}"

    run_user("rm -rf ~/.config/nsr-secret $XDG_RUNTIME_DIR/gnupg")
    machine.succeed("rm -f /var/log/journal/nsr-marker /run/docker.sock")
  '';
}
