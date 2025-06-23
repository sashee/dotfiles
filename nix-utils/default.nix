let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	outside_prgss = [
		(import ./keepassxc {})
	];

	prgss = [
		(import ./nvim {})
		(import ./aws {})
		(import ./npm {})
		(import ./lazygit {})
		(import ./vlc {})
	];

	prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) prgss));
	outside_prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) outside_prgss));

	fish = (import ./fish {inherit prgs;} {inherit pkgs;});
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = builtins.concatLists [(map (prg: prg.scripts) prgs) fish.scripts (map (prg: prg.scripts) outside_prgs)];
	}
