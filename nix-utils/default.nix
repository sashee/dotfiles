let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	prgs = [
		(import ./nvim {inherit pkgs;})
		(import ./npm {inherit pkgs;})
		(import ./npm/node.nix {inherit pkgs;})
		(import ./aws {inherit pkgs;})
		(import ./lazygit {inherit pkgs;})
	];

	fish = (import ./fish {inherit pkgs prgs;});
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = builtins.concatLists [(map (prg: prg.scripts) prgs) fish.scripts];
	}
