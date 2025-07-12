let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {allowUnfree = true;}; overlays = [
		# postInstallCheck fails on rpi kernel, disable it here
		(final: prev: {landrun = prev.landrun.overrideAttrs (old: {postInstallCheck = "";});})
	]; };

	prgss = [
		(import ./nvim {})
		(import ./aws {})
		(import ./npm {})
		(import ./lazygit {})
		(import ./vlc {})
		#(import ./vkquake {})
		#(import ./anyk {})
	];

	prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) prgss));

	outside_prgss = [
		(import ./keepassxc {})
		(import ./fish {inherit prgs;})
		(import ./libreoffice {inherit pkgs;})
	];

	outside_prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) outside_prgss));
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = builtins.concatLists [
			(map (prg: prg.scripts) prgs)
			(map (prg: prg.scripts) outside_prgs)
		];
	}
