let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	nvim = (import ./nvim {});
	npm = (import ./npm {});
	aws = (import ./aws {});
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = [nvim npm aws];
	}
