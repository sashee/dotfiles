# Generic NixOS-VM sandbox-test harness.
#
# The machine under test and the user are INPUTS — this file knows nothing about
# the dotfiles repo. It runs the (machine-agnostic) test cases against the given
# machine, as the given existing user. The same file is what an external repo
# imports to test the sandbox against its own configuration:
#
#   import "${dotfiles}/nix-utils/tests/lib.nix" {
#     inherit pkgs;
#     machineModules = [ self.nixosModules.common-desktop ];
#     user = "demo";   # an existing normal user on that machine
#   }
#   # => { sandbox = <shared VM>; <isolated-case> = <own VM>; ... }
#
# Two execution models (a case picks one):
#   - lightweight (default): runs as a subtest on ONE shared VM, booted once.
#   - isolated (`isolate = true`): gets its OWN VM, with optional extra
#     `machineModules` layered on the base machine (for setup / config changes).
#
# The dotfiles-specific machine assembly lives in ./default.nix, which calls this.
{
  pkgs,
  machineModules,
  user,
}:
let
  lib = pkgs.lib;

  # Layered onto the machine under test: ensure the user it runs as has a
  # lingering login session, so `/run/user/<uid>` (XDG_RUNTIME_DIR) exists —
  # required, because the sandbox runner expands the protected `$XDG_RUNTIME_DIR/*`
  # paths and fails closed if the var is unset. Forced because the test depends on
  # it; harmless on a test VM.
  ensureLinger = u: { lib, ... }: {
    users.users.${u}.linger = lib.mkForce true;
  };

  # Python preamble exposing `run_user(cmd, succeed=True)`. The user's uid is
  # discovered at runtime, so callers only need to name an existing user.
  preamble = u: ''
    import shlex

    USER = "${u}"

    machine.wait_for_unit("multi-user.target")
    uid = machine.succeed("id -u " + USER).strip()
    xdg = "/run/user/" + uid
    machine.wait_for_unit("user@" + uid + ".service")
    machine.wait_until_succeeds("test -d " + xdg)

    def run_user(cmd, succeed=True):
        # Run as the test user in a login shell (so /run/current-system/sw/bin is
        # on PATH) with XDG_RUNTIME_DIR set, then assert the exit status.
        wrapped = "export XDG_RUNTIME_DIR=" + xdg + "; " + cmd
        full = "su - " + USER + " -c " + shlex.quote(wrapped)
        return (machine.succeed if succeed else machine.fail)(full)

  '';

  # Build one VM test on the base machine plus any extra per-test modules.
  mkTest = { name, testScript, extraModules ? [ ] }: pkgs.testers.runNixOSTest {
    inherit name;
    # Don't pin nixpkgs.* read-only on the nodes, so a consumer's machineModules
    # may set nixpkgs.config (e.g. allowUnfree) / overlays without a types.unique
    # collision. Small eval-time cost; our own tester sets no nixpkgs.* options.
    node.pkgsReadOnly = false;
    nodes.machine = { imports = machineModules ++ extraModules ++ [ (ensureLinger user) ]; };
    testScript = (preamble user) + testScript;
  };

  # The case library: each case is
  #   { testScript; isolate ? false; machineModules ? []; }
  # independent of the machine.
  cases = {
    node-sibling-isolation = import ./cases/node-sibling-isolation.nix { inherit pkgs; };
    dev-baseline = import ./cases/dev-baseline.nix { inherit pkgs; };
    sandbox-nesting = import ./cases/sandbox-nesting.nix { inherit pkgs; };
    uds-connectable = import ./cases/uds-connectable.nix { inherit pkgs; };
    abstract-sockets = import ./cases/abstract-sockets.nix { inherit pkgs; };
    protected-paths = import ./cases/protected-paths.nix { inherit pkgs; };
    network-isolation = import ./cases/network-isolation.nix { inherit pkgs; };
    machine-id = import ./cases/machine-id.nix { inherit pkgs; };
    git-sandbox = import ./cases/git-sandbox.nix { inherit pkgs; };
    npm-cache-scoping = import ./cases/npm-cache-scoping.nix { inherit pkgs; };
    read-only-root = import ./cases/read-only-root.nix { inherit pkgs; };
    pid-namespace = import ./cases/pid-namespace.nix { inherit pkgs; };
  };

  isolated = lib.filterAttrs (_: c: c.isolate or false) cases;
  shared = lib.filterAttrs (_: c: !(c.isolate or false)) cases;

  # Wrap a lightweight case's testScript as an indented `with subtest(...)` block.
  subtestBlock = name: case:
    ''with subtest("${name}"):'' + "\n    "
    + builtins.replaceStrings [ "\n" ] [ "\n    " ] case.testScript;
  sharedBody = lib.concatStringsSep "\n\n" (lib.mapAttrsToList subtestBlock shared);

  # Each isolated case → its own VM, with its extra modules layered on.
  isolatedTests = lib.mapAttrs (name: c:
    mkTest {
      name = "nix-utils-${name}";
      testScript = c.testScript;
      extraModules = c.machineModules or [ ];
    }
  ) isolated;
in
  # `sandbox` is the reserved key for the shared VM running all lightweight cases
  # as subtests (omitted when there are none); plus one entry per isolated case.
  isolatedTests
  // lib.optionalAttrs (shared != { }) {
    sandbox = mkTest { name = "nix-utils-sandbox"; testScript = sharedBody; };
  }
