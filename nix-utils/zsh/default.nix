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
			--env ${consts.RESTRICT_TO_ENV_VAR_NAME} \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--unrestricted-network \
			--bind-tcp 8000 \
			--bind-tcp 8080 \
			--bind-tcp 8081 \
			--rwx $HOME/.local/share/zsh \
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
			--rwx ~/.local/share/freeorion \
			--rwx ~/.config/transmission \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.lib.strings.concatMapStringsSep "\n" (prg: prg.landrun_setup) prgs}
	'';


	get_before = {pkgs}: let
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
	in ''
	mkdir -p ~/.local/share/zsh/zsh_history
	export ZDOTDIR=${config}
	'';

	get_bin = {pkgs}: let
	in
	"${pkgs.zsh}/bin/zsh";
in
[
	(wrapper {
	 name = "zsh";
	 inherit get_landrun_requirements get_landrun_setup get_before get_bin;
	})
	(wrapper {
		name = "zsh-nonet";
		inherit get_landrun_setup get_before get_landrun_requirements;
		get_bin = {pkgs}: "${pkgs.landrun}/bin/landrun --best-effort --unrestricted-filesystem ${get_bin {inherit pkgs;}}";
		generate_unsafe = false;
	 })
]

