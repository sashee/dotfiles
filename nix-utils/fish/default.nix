{prgs}:
let
	wrapper = import ../wrapper.nix;
	consts = import ../consts.nix;
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
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--unrestricted-network \
			--bind-tcp 8000 \
			--bind-tcp 8080 \
			--rwx ~/.local/share/fish \
			--rwx ~/.config/fish \
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


	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: let
		config = pkgs.writeTextFile {
			name = "config.fish";
			text = ''
				fish_add_path $HOME/dotfiles/nix-utils/result/bin

# universal variables
set -U __fish_initialized 3800
set -U fish_color_autosuggestion brblack
set -U fish_color_cancel \x2dr
set -U fish_color_command normal
set -U fish_color_comment red
set -U fish_color_cwd green
set -U fish_color_cwd_root red
set -U fish_color_end green
set -U fish_color_error brred
set -U fish_color_escape brcyan
set -U fish_color_history_current \x2d\x2dbold
set -U fish_color_host normal
set -U fish_color_host_remote yellow
set -U fish_color_normal normal
set -U fish_color_operator brcyan
set -U fish_color_param cyan
set -U fish_color_quote yellow
set -U fish_color_redirection cyan\x1e\x2d\x2dbold
set -U fish_color_search_match white\x1e\x2d\x2dbackground\x3dbrblack
set -U fish_color_selection white\x1e\x2d\x2dbold\x1e\x2d\x2dbackground\x3dbrblack
set -U fish_color_status red
set -U fish_color_user brgreen
set -U fish_color_valid_path \x2d\x2dunderline
set -U fish_key_bindings fish_default_key_bindings
set -U fish_pager_color_completion normal
set -U fish_pager_color_description yellow\x1e\x2di
set -U fish_pager_color_prefix normal\x1e\x2d\x2dbold\x1e\x2d\x2dunderline
set -U fish_pager_color_progress brwhite\x1e\x2d\x2dbackground\x3dcyan
set -U fish_pager_color_selected_background \x2dr


				${pkgs.starship}/bin/starship init fish | source
			'';
		};
	in
	#"${pkgs.fish}/bin/fish --no-config --init-command 'source ${config}'";
	"${pkgs.fish}/bin/fish --init-command 'source ${config}'";
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
