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
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;

  # nixGL provides x86-only Intel/nvidia GL wrappers; nothing to wrap on aarch64,
  # so pass null (chromium/vkquake fall back to the unwrapped binary).
  nixgl = if isAarch64 then null
    else import (fetchTarball "https://github.com/nix-community/nixGL/archive/main.tar.gz") { inherit pkgs; };

  # Only tor-browser is genuinely x86-only in nixpkgs; keep everything else that
  # builds on aarch64 (unlike the headless rpi5 host, CI shouldn't assume headless).
  scriptsEnv = import ./lib.nix {
    inherit pkgs unstable nixgl;
    skip = if isAarch64 then [ "tor-browser" ] else [];
  };
  # Pass the already-built full env so the tools-smoke test can launch every tool
  # without rebuilding it (and with the same nixgl as the real env).
  tests = import ./tests { inherit pkgs unstable; fullEnv = scriptsEnv; };
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
