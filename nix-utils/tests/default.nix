# Dotfiles-specific test entry: assembles a minimal NixOS test image (a user plus
# the sandboxed tools the cases need) and runs the generic harness (./lib.nix)
# against it. Inputs are required (no fetchTarball) so this never fetches a channel
# — ../default.nix supplies them.
#
#   nix-build nix-utils -A tests.node-sibling-isolation
#   nix-build nix-utils -A tests.node-sibling-isolation.driverInteractive
#
# An external repo testing the sandbox against its OWN configuration imports
# ./lib.nix directly with its machine + user instead of going through this file.
{
  pkgs,
  unstable,
  stateVersion ? pkgs.lib.trivial.release,
}:
let
  # Build a tool module passing only the formals it declares, so e.g. npm's
  # `{ pkgs }:` doesn't choke while opencode/claude get `unstable`.
  callTool = pkgs.lib.callPackageWith { inherit pkgs unstable; };

  user = "tester";

  # Minimal machine: the user the cases run as, plus the sandboxed tools they need
  # on PATH (not the full scripts-env, so VMs stay small).
  testMachine = { ... }: {
    users.users.${user} = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [
      (pkgs.buildEnv {
        name = "nix-utils-test-tools";
        # node / node-nonet / npm come from npm; git for the git-sandbox case;
        # zsh for the sandbox-nesting case (a shell that re-sandboxes its children).
        paths = (callTool ../npm { }).scripts
          ++ (callTool ../git { }).scripts
          ++ (callTool ../zsh { }).scripts;
      })
    ];
    system.stateVersion = stateVersion;
  };
in
  import ./lib.nix {
    inherit pkgs;
    machineModules = [ testMachine ];
    inherit user;
  }
