{ pkgs }:
let
  rustSrc = import ../../rust-src.nix { inherit pkgs; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "nix-sandbox-runner";
  version = "0.1.0";

  src = rustSrc "_wrapper/runner";
  sourceRoot = "nix-utils/_wrapper/runner";

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
