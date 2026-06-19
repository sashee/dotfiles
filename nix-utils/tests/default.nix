# Dotfiles-specific test entry: assembles a NixOS test image (a user plus the
# sandboxed tools the cases need) and runs the generic harness (./lib.nix) against
# it. Inputs are required (no fetchTarball) so this never fetches a channel —
# ../default.nix supplies them.
#
#   nix-build nix-utils -A tests.sandbox        # all lightweight cases (one VM)
#   nix-build nix-utils -A tests.<isolated>     # an isolated case
#
# An external repo testing the sandbox against its OWN configuration imports
# ./lib.nix directly with its machine + user instead of going through this file.
{
  pkgs,
  unstable,
  nixgl ? null,
  # The full scripts-env (all sandboxed tools). ../default.nix passes its already
  # built one; the default builds it (nixgl=null) for standalone use. Installed on
  # the tester so the tools-smoke case can launch every tool.
  fullEnv ? import ../lib.nix { inherit pkgs unstable nixgl; },
  stateVersion ? pkgs.lib.trivial.release,
}:
let
  user = "tester";

  testMachine = { ... }: {
    users.users.${user} = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [ fullEnv ];
    # A session bus for the dbus-proxy-filter case: with the lingering tester user,
    # systemd --user registers org.freedesktop.systemd1 on /run/user/1000/bus.
    services.dbus.enable = true;
    system.stateVersion = stateVersion;
  };
in
  import ./lib.nix {
    inherit pkgs;
    machineModules = [ testMachine ];
    inherit user;
  }
