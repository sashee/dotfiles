{
	prgs ? [],
	pkgs,
}:
let
	consts = import ../consts.nix;

	# Base filesystem restrictions for zsh
	base_fs = {
		"/usr" = "rwx";
		"/dev" = "rwx";
		"/nix" = "rwx";
		"/etc" = "rwx";
		"/run" = "rwx";
		"/proc" = "rwx";
		"/sys" = "rwx";
		"/var" = "rwx";
		"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		"~/.local/share/zsh" = "rwx";
		"~/.cache" = "rwx";
		"~/.wine" = "rwx";
		"~/.vkquake" = "rwx";
		"~/.local/share/freeorion" = "rwx";
		"~/.config/freeorion" = "rwx";
		"~/.config/transmission" = "rwx";
	};

	base_env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "${consts.RESTRICT_TO_ENV_VAR_NAME}" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR" "ZDOTDIR"];

	# Merge landrun_restrictions from all programs
	# Skip programs with unrestricted access (empty landrun_restrictions)
	filtered_prgs = builtins.filter (prg: prg.landrun_restrictions != {}) prgs;

	merged_restrictions = builtins.foldl' (acc: prg:
		let
			prg_restrictions = prg.landrun_restrictions or {};
		in
		{
			fs = acc.fs // (prg_restrictions.fs or {});
			env = acc.env ++ (prg_restrictions.env or []);
		}
	) {
		fs = base_fs;
		env = base_env;
	} filtered_prgs;

	config = pkgs.writeTextDir ".zshrc" ''
export LANG="en_US.UTF-8"
export LC_COLLATE="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export LC_MESSAGES="en_US.UTF-8"
export LC_MONETARY="en_US.UTF-8"
export LC_NUMERIC="en_US.UTF-8"
export LC_TIME="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

export HISTFILE=$HOME/.local/share/zsh/zsh_history/.zsh_history

source <(${pkgs.fzf}/bin/fzf --zsh)

path+=('${pkgs.fzf}/bin')

export FZF_BASE=${pkgs.fzf}/share/fzf

ZSH_THEME="sunrise"
setopt HIST_IGNORE_ALL_DUPS
plugins=(
git
fzf
vi-mode
)
bindkey -M vicmd "^V" edit-command-line
export EDITOR='nvim'

fpath+=${pkgs.zsh-completions}/share/zsh/site-functions
autoload -U compinit && compinit

source ${pkgs.oh-my-zsh}/share/oh-my-zsh/oh-my-zsh.sh

autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search # Up
bindkey "^[[B" down-line-or-beginning-search # Down

export DISABLE_FZF_KEY_BINDINGS="true"

bindkey '^P' fzf-history-widget

autoload -U +X bashcompinit && bashcompinit

export PROMPT="$PROMPT_PREF$PROMPT"
	'';

	bin = "${pkgs.zsh}/bin/zsh";

	before = ''
	mkdir -p ~/.local/share/zsh/zsh_history
	export ZDOTDIR=${config}
	'';

	landrun_setup = ''
		${builtins.concatStringsSep "\n" (map (prg: prg.landrun_setup or "") prgs)}
	'';

	zsh_scripts = (import ../wrapper.nix {
		name = "zsh";
		inherit pkgs bin;
		landrun_restrictions = merged_restrictions;
		inherit before landrun_setup;
	}).scripts;

	zsh_nonet_fullfs_scripts = (import ../wrapper.nix {
		name = "zsh-nonet-fullfs";
		inherit pkgs bin;
		landrun_restrictions = {};  # unrestricted filesystem and network
		inherit before landrun_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = zsh_scripts ++ zsh_nonet_fullfs_scripts;
	landrun_restrictions = merged_restrictions;
}
