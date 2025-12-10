let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.11";
  pkgs = import nixpkgs { config = {allowUnfree = true;}; overlays = []; };

	nvim = import ./nvim/default.nix { inherit pkgs; };

	# Programs to pass to zsh for dynamic requirements merging
	zsh_programs = [
		(import ./aws/default.nix { inherit pkgs; })
		(import ./awslogs/default.nix { inherit pkgs; })
		(import ./duckdb/default.nix { inherit pkgs; })
		(import ./flameshot/default.nix { inherit pkgs; })
		(import ./fx/default.nix { inherit pkgs; })
		(import ./isd/default.nix { inherit pkgs; })
		#(import ./k2pdfopt/default.nix { inherit pkgs; })
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

	consts = import ./consts.nix;

	# Get all scripts from all programs
	allScripts = builtins.concatLists (map (p: p.scripts) programs);
	
	# Filter to only *-info scripts (by checking if name ends with -info)
	infoScripts = builtins.filter (s: pkgs.lib.hasSuffix "-info" s.name) allScripts;

	# Script to run all -info programs and create a table
	allInfoScript = pkgs.writeScriptBin "all-info" ''
		#!${pkgs.bash}/bin/bash
		
		# Collect all JSON outputs
		json_outputs=""
		${builtins.concatStringsSep "\n" (map (s: ''
		output=$(${pkgs.coreutils}/bin/timeout 10s ${s}/bin/${s.name} 2>/dev/null)
		if [ -n "$output" ]; then
			if [ -n "$json_outputs" ]; then
				json_outputs="$json_outputs,$output"
			else
				json_outputs="$output"
			fi
		fi
		'') infoScripts)}
		
		# Create array and restructure JSON with nested objects for visidata
		echo "[$json_outputs]" | ${pkgs.jq}/bin/jq '[.[] | {
			name,
			network_access,
			real_dev,
			seccomp,
			share: {
				user: .share_user,
				uts: .share_uts,
				cgroup: .share_cgroup,
				pid: .share_pid,
				ipc: .share_ipc
			},
			protected_paths
		}]' | ${pkgs.bubblewrap}/bin/bwrap \
			--unshare-all \
			--ro-bind / / \
			--dev /dev \
			--proc /proc \
			--die-with-parent \
			${pkgs.visidata}/bin/vd -f json
	'';
in
	pkgs.buildEnv {
		name = "scripts-env";
		paths = builtins.concatLists (map (p: p.scripts) programs) ++ [allInfoScript];
	}
