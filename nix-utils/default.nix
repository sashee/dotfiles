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
		(import ./isd {})
		(import ./vlc {})
		(import ./fx {})
		(import ./duckdb {})
		(import ./bluetuith {})
		(import ./chromium {})
		(import ./flameshot {})
		(import ./k2pdfopt {})
		(import ./lazysql {})
		(import ./magic-wormhole {})
		(import ./opencode {})
		(import ./github-copilot-cli {})
		#(import ./vkquake {})
		#(import ./anyk {})
	];

	prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) prgss));

	outside_prgss = rec {
		keepassxc = (import ./keepassxc {});
		#fish = (import ./fish {inherit prgs;});
		zsh = (import ./zsh {inherit prgs;});
		libreoffice = (import ./libreoffice {inherit pkgs;});
		tmux = (import ./tmux {inherit zsh;});
	};

	outside_prgs = map (a: a {inherit pkgs;}) (builtins.concatLists (map (prg: pkgs.lib.toList prg) (builtins.attrValues outside_prgss)));
in
	pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = builtins.concatLists [
			(map (prg: prg.scripts) prgs)
			(map (prg: prg.scripts) outside_prgs)
		];
	}
