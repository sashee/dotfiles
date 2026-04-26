let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.11";
  pkgs = import nixpkgs { config = {allowUnfree = true;}; overlays = []; };
  nixglSrc = fetchTarball "https://github.com/nix-community/nixGL/archive/main.tar.gz";
  nixgl = import nixglSrc { inherit pkgs; };

	nvim = import ./nvim/default.nix { inherit pkgs; };

	# Programs to pass to zsh for dynamic requirements merging
	zsh_programs = [
		(import ./aws/default.nix { inherit pkgs; })
		(import ./awslogs/default.nix { inherit pkgs; })
		(import ./duckdb/default.nix { inherit pkgs; })
		(import ./sqlite3/default.nix { inherit pkgs; })
		(import ./flameshot/default.nix { inherit pkgs; })
		(import ./fx/default.nix { inherit pkgs; })
		(import ./isd/default.nix { inherit pkgs nvim; })
		(import ./k2pdfopt/default.nix { inherit pkgs; })
		(import ./lazygit/default.nix { inherit pkgs; })
		(import ./lazysql/default.nix { inherit pkgs; })
		(import ./magic-wormhole/default.nix { inherit pkgs; })
		(import ./opencode/default.nix { inherit pkgs; })
		(import ./vlc/default.nix { inherit pkgs; })
		nvim
		(import ./npm/default.nix { inherit pkgs; })
		(import ./qrread/default.nix { inherit pkgs; })
		(import ./libreoffice/default.nix { inherit pkgs; })
	];

	# Programs not passed to zsh (have unrestricted filesystem)
	other_programs = [
		(import ./chromium/default.nix { inherit pkgs nixgl; })
		(import ./tor-browser/default.nix { inherit pkgs; })
		(import ./keepassxc/default.nix { inherit pkgs; })
		(import ./bluetuith/default.nix { inherit pkgs; })
		(import ./vkquake/default.nix { inherit pkgs nixgl; })
	];

	zsh = import ./zsh/default.nix { inherit pkgs; prgs = zsh_programs; };
	tmux = import ./tmux/default.nix { inherit zsh pkgs; };
	zellij = import ./zellij/default.nix { inherit zsh pkgs nvim; };

	programs = zsh_programs ++ other_programs ++ [zsh tmux zellij];

	consts = import ./consts.nix;

	# Get all scripts from all programs
	allScripts = builtins.concatLists (map (p: p.scripts) programs);
	
	# Filter to only *-info scripts (by checking if name ends with -info)
	infoScripts = builtins.filter (s: pkgs.lib.hasSuffix "-info" s.name) allScripts;

 	# Import all-info script from separate file
 	allInfoScript = import ./all-info.nix { inherit pkgs; inherit infoScripts; };
 in
 	pkgs.buildEnv {
 		name = "scripts-env";
 		paths = builtins.concatLists (map (p: p.scripts) programs) ++ [allInfoScript.all-info allInfoScript.all-info-json];
 	}
