{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "nix-sandbox-runner";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
