# Convenience entrypoint for `nix-build nix-utils`. The ONLY place channels are
# fetched — everything else takes pkgs/unstable/nixgl explicitly (see ./lib.nix).
#
# Building this builds the scripts-env AND runs the NixOS VM tests (the check):
#   nix-build nix-utils                              # env + tests
#   nix-build nix-utils -A scriptsEnv                # env only (skip the VM test)
#   nix-build nix-utils -A tests.node-sibling-isolation
let
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-26.05") {
    config = { allowUnfree = true; };
    overlays = [];
  };
  unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable") {
    config = { allowUnfree = true; };
    overlays = [];
  };
  nixgl = import (fetchTarball "https://github.com/nix-community/nixGL/archive/main.tar.gz") { inherit pkgs; };

  scriptsEnv = import ./lib.nix { inherit pkgs unstable nixgl; };
  tests = import ./tests { inherit pkgs unstable; };
in
  pkgs.symlinkJoin {
    name = "scripts-env";
    paths = [ scriptsEnv ];
    # Interpolating each VM-test derivation's store path registers it as a build
    # input, so building the env requires every test to pass.
    postBuild = ''
      : ${pkgs.lib.concatStringsSep " " (map (t: "${t}") (builtins.attrValues tests))}
    '';
    passthru = { inherit scriptsEnv tests; };
  }
