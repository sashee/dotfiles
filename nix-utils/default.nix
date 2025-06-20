let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	nvim = (import ./nvim {inherit pkgs;});
	npm = (import ./npm {inherit pkgs;});
	aws = (import ./aws {inherit pkgs;});
	lazygit = (import ./lazygit {inherit pkgs;});
	fish = (import ./fish {inherit pkgs;});
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = [nvim.scripts npm.scripts aws.scripts lazygit.scripts fish];
	}
