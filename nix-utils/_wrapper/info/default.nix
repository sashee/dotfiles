{ pkgs }:
let
  rustSrc = import ../../rust-src.nix { inherit pkgs; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "nix-sandbox-info";
  version = "0.1.0";

  src = rustSrc "_wrapper/info";
  sourceRoot = "nix-utils/_wrapper/info";

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
