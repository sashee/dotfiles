{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "nix-sandbox-info";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
