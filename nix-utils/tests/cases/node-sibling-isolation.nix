# Case: the sandboxed `node` confines the filesystem to the current folder.
#
# `node` is wrapped with restrict_to_current_folder = true. The base sandbox does
# `--ro-bind / / ; --tmpfs /home` and re-binds only the cwd, so from /home/A node
# can read its own files but a sibling /home/B is masked by the /home tmpfs.
#
# Machine-agnostic: only assumes `node` is on PATH (installed by the machine
# under test, e.g. via the dotfiles nix-utils module).
{ pkgs }:
let
  # Reads the file named by argv[2], relative to cwd, to stdout. A plain script
  # file avoids `node -e` quoting; its store path is readable via `--ro-bind / /`.
  readJs = pkgs.writeText "read.js" ''
    const fs = require("fs");
    process.stdout.write(fs.readFileSync(process.argv[2], "utf8"));
  '';
in
{
  testScript = ''
      # Two sibling dirs under the test user's home.
      run_user("mkdir -p ~/A ~/B")
      run_user("echo hello > ~/A/a.txt")
      run_user("echo TOPSECRET > ~/B/secret.txt")

      # Control: node can read a file in its own (current) directory.
      out = run_user("cd ~/A && node ${readJs} a.txt")
      assert "hello" in out, f"expected to read own file, got: {out!r}"

      # Isolation: node cannot read the sibling directory (masked by /home tmpfs).
      err = run_user("cd ~/A && node ${readJs} ../B/secret.txt", succeed=False)
      assert "TOPSECRET" not in err, "sibling file leaked into the sandbox!"
  '';
}
