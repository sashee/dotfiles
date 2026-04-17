{ pkgs }:
let
  rustSrc = import ../../rust-src.nix { inherit pkgs; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "nix-sandbox-all-info";
  version = "0.1.0";

  src = rustSrc "_wrapper/all-info";
  sourceRoot = "nix-utils/_wrapper/all-info";

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
