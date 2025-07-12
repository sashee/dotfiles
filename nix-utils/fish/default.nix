{prgs}:
let
	wrapper = import ../wrapper.nix;
	consts = import ../consts.nix;
	ORIGINAL_XDG_CONFIG_HOME_VAR_NAME = "__NIX_UTILS_ORIGINAL_XDG_CONFIG_HOME";
	get_landrun_requirements = {pkgs}: ''
			--rwx /usr,/dev,/nix,/etc,/run,/proc,/sys,/var \
			--rwx ''$${consts.RESTRICT_TO_ENV_VAR_NAME} \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env STARSHIP_CONFIG \
			--env ${consts.RESTRICT_TO_ENV_VAR_NAME} \
			--env ${ORIGINAL_XDG_CONFIG_HOME_VAR_NAME} \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--rwx ~/.local/share/fish \
			--unrestricted-network \
			--bind-tcp 8000 \
			--bind-tcp 8080 \
			${pkgs.lib.strings.concatMapStringsSep "\\\n" (req: '' \
			${pkgs.lib.strings.concatStringsSep " \\\n " req.requirements}'') (map (prg: {name = prg.name; requirements = (
			(builtins.filter (l: !(pkgs.lib.strings.hasInfix "--unrestricted-filesystem") l)
				(map pkgs.lib.strings.trim
					(pkgs.lib.strings.splitString "\\\n" prg.landrun_requirements)
				)
			)
			);}) prgs)} \
			--rwx ~/.cache \
			--rwx ~/.wine \
			--rwx ~/.vkquake \
			--rwx ~/.config/transmission \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.lib.strings.concatMapStringsSep "\n" (prg: prg.landrun_setup) prgs}
	'';


	get_before = {pkgs}: let
	config = pkgs.writeTextFile {
		name = "config.fish";
		text = ''
fish_add_path $HOME/dotfiles/nix-utils/result/bin

set -x XDG_CONFIG_HOME ''$${ORIGINAL_XDG_CONFIG_HOME_VAR_NAME}
set --erase ${ORIGINAL_XDG_CONFIG_HOME_VAR_NAME}

${pkgs.starship}/bin/starship init fish | source
		'';
	};

	starship_config = pkgs.writeTextFile {
		name = "starship.toml";
		text = ''
		'';
	};

	in ''
export ${ORIGINAL_XDG_CONFIG_HOME_VAR_NAME}=$XDG_CONFIG_HOME
export XDG_CONFIG_HOME=$(${pkgs.coreutils}/bin/mktemp -d)
export STARSHIP_CONFIG=${starship_config}

${pkgs.coreutils}/bin/mkdir -p $XDG_CONFIG_HOME/fish
${pkgs.coreutils}/bin/ln -s ${config} $XDG_CONFIG_HOME/fish/config.fish
	'';

	get_bin = {pkgs}: "${pkgs.fish}/bin/fish";
in
[
	(wrapper {
	 name = "fish";
	 inherit get_landrun_requirements get_landrun_setup get_before get_bin;
	})
	(wrapper {
		name = "fish-nonet";
		inherit get_landrun_setup get_before get_landrun_requirements;
		get_bin = {pkgs}: "${pkgs.landrun}/bin/landrun --best-effort --unrestricted-filesystem ${get_bin {inherit pkgs;}}";
		generate_unsafe = false;
	 })
]
