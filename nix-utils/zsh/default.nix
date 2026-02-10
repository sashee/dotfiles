{
	prgs ? [],
	pkgs,
}:
let
	consts = import ../consts.nix;

	# Base filesystem restrictions for zsh
	# Note: bwrap does --ro-bind / / so system paths are already available read-only
	# We only need to specify home directory paths that need write access
	base_fs = {
		"$HOME/.local/share/zsh" = "rw";
		"$HOME/.cache" = "rw";
		"$HOME/.wine" = "rw";
		"$HOME/.vkquake" = "rw";
		"$HOME/.local/share/freeorion" = "rw";
		"$HOME/.config/freeorion" = "rw";
		"$HOME/.config/transmission" = "rw";
	};


	# Merge sandbox_restrictions from all programs
	# Skip programs with unrestricted access (empty sandbox_restrictions)
	filtered_prgs = builtins.filter (prg: prg.sandbox_restrictions != {}) prgs;

	merged_restrictions = builtins.foldl' (acc: prg:
		let
			prg_restrictions = prg.sandbox_restrictions or {};
		in
		{
			fs = acc.fs // (prg_restrictions.fs or {});
			files = acc.files // (prg_restrictions.files or {});
		}
	) {
		fs = base_fs;
		files = {};
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
	${pkgs.coreutils}/bin/mkdir -p $HOME/.local/share/zsh/zsh_history
	export ZDOTDIR=${config}
	'';

	sandbox_setup = ''
		${builtins.concatStringsSep "\n" (map (prg: prg.sandbox_setup or "") prgs)}
	'';

	zsh_scripts = (import ../_wrapper/default.nix {
		name = "zsh";
		inherit pkgs bin;
		sandbox_restrictions = merged_restrictions // { network = true; allow_nested_sandbox = true; share_pid = true; };  # with network
		inherit before sandbox_setup;
	}).scripts;

 	zsh_nonet_scripts = (import ../_wrapper/default.nix {
  		name = "zsh-nonet";
  		inherit pkgs bin;
  		sandbox_restrictions = merged_restrictions // { allow_nested_sandbox = true; share_pid = true; };  # same fs/env as zsh, no network (no network key)
  		inherit before sandbox_setup;
  		generate_unsafe = false;
  	}).scripts;
 in
 {
 	scripts = zsh_scripts ++ zsh_nonet_scripts;
 	sandbox_restrictions = merged_restrictions;
 	sandbox_setup = sandbox_setup;
 }
