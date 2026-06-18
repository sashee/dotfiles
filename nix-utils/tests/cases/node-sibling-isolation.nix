# Case: the sandboxed `node` confines the filesystem to the current folder.
#
# `node` is wrapped with restrict_to_current_folder = true. The base sandbox does
# `--ro-bind / / ; --tmpfs /home` and re-binds only the cwd, so from ~/A node can
# read its own files but a sibling ~/B is masked by the /home tmpfs.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
in
{
  testScript = ''
    run_user("mkdir -p ~/A ~/B")
    run_user("echo hello > ~/A/a.txt")
    run_user("echo TOPSECRET > ~/B/secret.txt")

    # Control: node can read a file in its own (current) directory.
    out = run_user("cd ~/A && node ${probes.readFile} a.txt")
    assert "hello" in out, f"expected to read own file, got: {out!r}"

    # Isolation: node cannot read the sibling directory (masked by /home tmpfs).
    err = run_user("cd ~/A && node ${probes.readFile} ../B/secret.txt", succeed=False)
    assert "TOPSECRET" not in err, "sibling file leaked into the sandbox!"

    run_user("rm -rf ~/A ~/B")
  '';
}
