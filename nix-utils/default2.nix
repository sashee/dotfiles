let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {allowUnfree = true;}; overlays = [
		# postInstallCheck fails on rpi kernel, disable it here
		(final: prev: {landrun = prev.landrun.overrideAttrs (old: {postInstallCheck = "";});})
	]; };

	# Programs to pass to zsh for dynamic requirements merging
	zsh_programs = [
		(import ./aws/v2.nix { inherit pkgs; })
		(import ./duckdb/v2.nix { inherit pkgs; })
		(import ./flameshot/v2.nix { inherit pkgs; })
		(import ./fx/v2.nix { inherit pkgs; })
		(import ./isd/v2.nix { inherit pkgs; })
		(import ./k2pdfopt/v2.nix { inherit pkgs; })
		(import ./lazygit/v2.nix { inherit pkgs; })
		(import ./lazysql/v2.nix { inherit pkgs; })
		(import ./magic-wormhole/v2.nix { inherit pkgs; })
		(import ./opencode/v2.nix { inherit pkgs; })
		(import ./vlc/v2.nix { inherit pkgs; })
		(import ./nvim/v2.nix { inherit pkgs; })
		(import ./npm/v2.nix { inherit pkgs; })
	];

	# Programs not passed to zsh (have unrestricted filesystem)
	other_programs = [
		(import ./chromium/v2.nix { inherit pkgs; })
		(import ./keepassxc/v2.nix { inherit pkgs; })
		(import ./libreoffice/v2.nix { inherit pkgs; })
		(import ./bluetuith/v2.nix { inherit pkgs; })
	];

	zsh = import ./zsh/v2.nix { inherit pkgs; prgs = zsh_programs; };
	tmux = import ./tmux/v2.nix { inherit zsh pkgs; };

	programs = zsh_programs ++ other_programs ++ [zsh tmux];
in
	pkgs.buildEnv {
		name = "scripts-env";
		paths = builtins.concatLists (map (p: p.scripts) programs);
	}
