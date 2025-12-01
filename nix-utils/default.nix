let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {allowUnfree = true;}; overlays = [
		# postInstallCheck fails on rpi kernel, disable it here
		(final: prev: {landrun = prev.landrun.overrideAttrs (old: {postInstallCheck = "";});})
	]; };

	nvim = import ./nvim/default.nix { inherit pkgs; };

	# Programs to pass to zsh for dynamic requirements merging
	zsh_programs = [
		(import ./aws/default.nix { inherit pkgs; })
		(import ./awslogs/default.nix { inherit pkgs; })
		(import ./duckdb/default.nix { inherit pkgs; })
		(import ./flameshot/default.nix { inherit pkgs; })
		(import ./fx/default.nix { inherit pkgs; })
		(import ./isd/default.nix { inherit pkgs; })
		(import ./k2pdfopt/default.nix { inherit pkgs; })
		(import ./lazygit/default.nix { inherit pkgs; })
		(import ./lazysql/default.nix { inherit pkgs; })
		(import ./magic-wormhole/default.nix { inherit pkgs; })
		(import ./opencode/default.nix { inherit pkgs; })
		(import ./vlc/default.nix { inherit pkgs; })
		nvim
		(import ./npm/default.nix { inherit pkgs; })
	];

	# Programs not passed to zsh (have unrestricted filesystem)
	other_programs = [
		(import ./chromium/default.nix { inherit pkgs; })
		(import ./keepassxc/default.nix { inherit pkgs; })
		(import ./libreoffice/default.nix { inherit pkgs; })
		(import ./bluetuith/default.nix { inherit pkgs; })
	];

	zsh = import ./zsh/default.nix { inherit pkgs; prgs = zsh_programs; };
	tmux = import ./tmux/default.nix { inherit zsh pkgs; };
	zellij = import ./zellij/default.nix { inherit zsh pkgs nvim; };

	programs = zsh_programs ++ other_programs ++ [zsh tmux zellij];
in
	pkgs.buildEnv {
		name = "scripts-env";
		paths = builtins.concatLists (map (p: p.scripts) programs);
	}
