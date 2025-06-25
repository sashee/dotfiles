{prgs}:
let
	wrapper = import ../wrapper.nix;
	get_landrun_requirements = {pkgs}: ''
			--rwx /usr,/dev,/nix,/etc,/run,/proc,/sys \
			--rwx ''$RESTRICT_TO \
			--rwx "''${TMPDIR:-/tmp}" \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env XDG_CONFIG_HOME \
			--env __NIX_UTILS_ORIGINAL_XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--rwx ~/.local/share/fish \
			--unrestricted-network \
			--bind-tcp 8000 \
			--bind-tcp 8080 \
			${pkgs.lib.strings.concatMapStringsSep "\\\n" (prg: prg.landrun_requirements) prgs} \
			--rwx ~/.cache \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.lib.strings.concatMapStringsSep "\n" (prg: prg.landrun_setup) prgs}
	'';


	get_before = {pkgs}: let
	config = pkgs.writeTextFile {
		name = "config.fish";
		text = ''
fish_add_path $HOME/dotfiles/nix-utils/result/bin
set -x XDG_CONFIG_HOME $__NIX_UTILS_ORIGINAL_XDG_CONFIG_HOME
set --erase __NIX_UTILS_ORIGINAL_XDG_CONFIG_HOME

${pkgs.starship}/bin/starship init fish | source
		'';
	};

	in ''
export __NIX_UTILS_ORIGINAL_XDG_CONFIG_HOME=$XDG_CONFIG_HOME
export XDG_CONFIG_HOME=$(${pkgs.coreutils}/bin/mktemp -d)

${pkgs.coreutils}/bin/mkdir -p $XDG_CONFIG_HOME/fish
${pkgs.coreutils}/bin/ln -s ${config} $XDG_CONFIG_HOME/fish/config.fish
${pkgs.coreutils}/bin/ln -s ${./functions} $XDG_CONFIG_HOME/fish/functions
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
		get_bin = {pkgs}: "${pkgs.landrun}/bin/landrun --unrestricted-filesystem ${get_bin {inherit pkgs;}}";
		generate_unsafe = false;
	 })
]
