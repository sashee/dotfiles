{
	prgs ? [],
	pkgs,
}:
let
	consts = import ../consts.nix;
	launcher = import ../launcher.nix { inherit pkgs; };

	# Base filesystem restrictions for zsh
	# Note: bwrap does --ro-bind / / so system paths are already available read-only
	# We only need to specify home directory paths that need write access
	base_fs = {
		"$HOME/.local/share/zsh" = { perm = "rw"; mkdir = true; };
		"$HOME/.cache" = { perm = "rw"; };
		"$HOME/.wine" = { perm = "rw"; };
		"$HOME/.vkquake" = { perm = "rw"; };
		"$HOME/.local/share/freeorion" = { perm = "rw"; };
		"$HOME/.config/freeorion" = { perm = "rw"; };
		"$HOME/.config/transmission" = { perm = "rw"; };
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

	bin = launcher.mkLauncher {
		name = "zsh";
		target = "${pkgs.zsh}/bin/zsh";
		setEnv = {
			ZDOTDIR = "${config}";
			"${consts.SKIP_SANDBOX_ENV_VAR_NAME}" = "false";
		};
	};

	zsh_scripts = (import ../_wrapper/default.nix {
		name = "zsh";
		inherit pkgs bin;
		sandbox_restrictions = merged_restrictions // { network = true; share_pid = true; };  # with network
	}).scripts;

  	zsh_nonet_scripts = (import ../_wrapper/default.nix {
  		name = "zsh-nonet";
	  		inherit pkgs bin;
		  		sandbox_restrictions = merged_restrictions // { share_pid = true; };  # same fs/env as zsh, no network (no network key)
	  		generate_unsafe = false;
	  	}).scripts;
 in
 {
 	scripts = zsh_scripts ++ zsh_nonet_scripts;
 	sandbox_restrictions = merged_restrictions;
 }
