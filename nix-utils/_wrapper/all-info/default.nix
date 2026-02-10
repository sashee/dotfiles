{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "nix-sandbox-all-info";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
