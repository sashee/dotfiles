let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {allowUnfree = true;}; overlays = [
		# postInstallCheck fails on rpi kernel, disable it here
		(final: prev: {landrun = prev.landrun.overrideAttrs (old: {postInstallCheck = "";});})
	]; };
	awsv2 = import ./aws/v2.nix {
		inherit pkgs;
	};
	bluetuith = import ./bluetuith/v2.nix {
		inherit pkgs;
	};
	chromium = import ./chromium/v2.nix {
		inherit pkgs;
	};
	duckdb = import ./duckdb/v2.nix {
		inherit pkgs;
	};
	flameshot = import ./flameshot/v2.nix {
		inherit pkgs;
	};
	fx = import ./fx/v2.nix {
		inherit pkgs;
	};
	isd = import ./isd/v2.nix {
		inherit pkgs;
	};
	k2pdfopt = import ./k2pdfopt/v2.nix {
		inherit pkgs;
	};
	keepassxc = import ./keepassxc/v2.nix {
		inherit pkgs;
	};
	lazygit = import ./lazygit/v2.nix {
		inherit pkgs;
	};
	lazysql = import ./lazysql/v2.nix {
		inherit pkgs;
	};
	libreoffice = import ./libreoffice/v2.nix {
		inherit pkgs;
	};
	magicwormhole = import ./magic-wormhole/v2.nix {
		inherit pkgs;
	};
	opencode = import ./opencode/v2.nix {
		inherit pkgs;
	};
	vlc = import ./vlc/v2.nix {
		inherit pkgs;
	};
	nvim = import ./nvim/v2.nix {
		inherit pkgs;
	};
	npm = import ./npm/v2.nix {
		inherit pkgs;
	};
in
	pkgs.buildEnv {
		name = "scripts-env";
		paths = awsv2.scripts ++ bluetuith.scripts ++ chromium.scripts ++ duckdb.scripts ++ flameshot.scripts ++ fx.scripts ++ isd.scripts ++ k2pdfopt.scripts ++ keepassxc.scripts ++ lazygit.scripts ++ lazysql.scripts ++ libreoffice.scripts ++ magicwormhole.scripts ++ opencode.scripts ++ vlc.scripts ++ nvim.scripts ++ npm.scripts;
	}
