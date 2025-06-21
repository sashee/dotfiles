let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	prgss = [
		(import ./nvim {})
		(import ./aws {})
		(import ./npm {})
		(import ./lazygit {})
		(import ./vlc {})
	];

	prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) prgss));

	fish = (import ./fish {inherit prgs;} {inherit pkgs;});
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = builtins.concatLists [(map (prg: prg.scripts) prgs) fish.scripts];
	}
