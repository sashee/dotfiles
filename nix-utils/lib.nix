# All nix-utils build logic. Takes the package sets explicitly with NO defaults,
# so a caller that forgets one gets an eval error rather than silently fetching a
# channel. The only place channels are fetched is the thin ./default.nix wrapper.
#
# `skip` is a list of program names to drop from the env (instead of commenting
# out their imports). Unknown names error (typo guard). Filtering is lazy: a
# skipped program's import is never forced (e.g. skipping chromium won't force
# nixgl). Programs are held in name-keyed attrsets so duplicate names are an eval
# error (uniqueness guaranteed). git/nvim are kept as let-bindings AND attrset
# entries because isd/lazygit/zellij depend on them directly, so skipping them
# only removes them from the env, never breaks those deps. zsh/tmux/zellij are
# always included.
{ pkgs, unstable, nixgl, skip ? [] }:
let

	nvim = import ./nvim/default.nix { inherit pkgs; };
	git = import ./git/default.nix { inherit pkgs; };

	# Programs passed to zsh for dynamic requirements merging.
	zshPrograms = {
		aws = import ./aws/default.nix { inherit pkgs; };
		awslogs = import ./awslogs/default.nix { inherit pkgs; };
		duckdb = import ./duckdb/default.nix { inherit pkgs; };
		sqlite3 = import ./sqlite3/default.nix { inherit pkgs; };
		flameshot = import ./flameshot/default.nix { inherit pkgs; };
		fx = import ./fx/default.nix { inherit pkgs; };
		inherit git nvim;
		isd = import ./isd/default.nix { inherit pkgs nvim; };
		k2pdfopt = import ./k2pdfopt/default.nix { inherit pkgs; };
		lazygit = import ./lazygit/default.nix { inherit pkgs git; };
		lazysql = import ./lazysql/default.nix { inherit pkgs; };
		magic-wormhole = import ./magic-wormhole/default.nix { inherit pkgs; };
		opencode = import ./opencode/default.nix { inherit pkgs unstable; };
		claude = import ./claude/default.nix { inherit pkgs unstable; };
		vlc = import ./vlc/default.nix { inherit pkgs; };
		npm = import ./npm/default.nix { inherit pkgs; };
		jwt = import ./jwt/default.nix { inherit pkgs; };
		libreoffice = import ./libreoffice/default.nix { inherit pkgs; };
	};

	# Programs not passed to zsh (have unrestricted filesystem).
	otherPrograms = {
		chromium = import ./chromium/default.nix { inherit pkgs nixgl; };
		tor-browser = import ./tor-browser/default.nix { inherit pkgs; };
		keepassxc = import ./keepassxc/default.nix { inherit pkgs; };
		bluetuith = import ./bluetuith/default.nix { inherit pkgs; };
		vkquake = import ./vkquake/default.nix { inherit pkgs nixgl; };
		qrread = import ./qrread/default.nix { inherit pkgs; };
	};

	knownNames = builtins.attrNames (zshPrograms // otherPrograms);
	unknownSkips = builtins.filter (n: !(builtins.elem n knownNames)) skip;
	keep = set: builtins.attrValues (builtins.removeAttrs set skip);

	zsh_programs = keep zshPrograms;
	other_programs = keep otherPrograms;

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
	pkgs.lib.throwIf (unknownSkips != [])
		"lib.nix: unknown skip name(s): ${builtins.concatStringsSep ", " unknownSkips} (known: ${builtins.concatStringsSep ", " knownNames})"
	(pkgs.buildEnv {
		name = "scripts-env";
		paths = builtins.concatLists (map (p: p.scripts) programs) ++ [allInfoScript.all-info allInfoScript.all-info-json];
	})
