{
	prgs ? [],
	pkgs,
}:
let
	consts = import ../consts.nix;
	launcher = import ../launcher.nix { inherit pkgs; };
	dev_allowlist = [ "/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm"];

	# Base filesystem restrictions for zsh
	# Note: bwrap does --ro-bind / / so system paths are already available read-only
	# We only need to specify home directory paths that need write access
	base_fs = {
		"$HOME/.local/share/zsh" = { perm = "rw"; mkdir = true; };
		"$HOME/.cache" = { perm = "rw"; };
		"$HOME/.wine" = { perm = "rw"; };
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
		# Carry real_machine_id through the merge so journal-readers (isd) make
		# the shells keep the real machine-id (journalctl needs it).
		real_machine_id = acc.real_machine_id || (prg_restrictions.real_machine_id or false);
		}
	) {
		fs = base_fs;
		files = {};
		real_machine_id = false;
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

# Expose the laptop's host-tools-mcp registry socket(s) on a remote box over a
# single ssh connection (one agent ack, no ControlMaster). The remote login
# shell inherits HOST_TOOLS_MCP_SOCKETS, so running `mcp-register-prefix sh -c`
# there registers a shell tool back to every local MCP client (Claude/OpenCode).
claude-remote() {
  emulate -L zsh
  setopt local_options pipefail err_return
  local target="$1"
  [[ -n "$target" ]] || { print -u2 "usage: claude-remote <user@host>"; return 2; }

  # Snapshot connectable laptop sockets (point-in-time, like a local
  # mcp-register run). (N=) => nullglob + sockets only.
  local root="''${TMPDIR:-/tmp}/host-tools-mcp"
  local -a socks; local s
  for s in "$root"/*/registry.sock(N=); do
    if command -v socat >/dev/null 2>&1; then
      if socat -T1 -u OPEN:/dev/null UNIX-CONNECT:"$s" >/dev/null 2>&1; then
        socks+=("$s")
      fi
    else
      socks+=("$s")
    fi
  done
  (( ''${#socks} )) || { print -u2 "claude-remote: no live host-tools-mcp servers; start Claude/OpenCode first"; return 1; }

  # One reverse forward per laptop socket -> a flat remote path (parent /tmp
  # exists, so no pre-mkdir / master needed); build the remote env value.
  local sid="cr-$$-$RANDOM"
  local -a rflags; local remote_env="" i=0 rp
  for s in "''${socks[@]}"; do
    rp="/tmp/$sid-$i.sock"
    rflags+=(-R "$rp:$s")
    remote_env="''${remote_env:+$remote_env:}$rp"
    i=$(( i + 1 ))
  done

  print -u2 "claude-remote: forwarding ''${#socks} socket(s); run 'mcp-register-prefix sh -c' on the remote when ready"
  ssh -t \
    -o StreamLocalBindUnlink=yes \
    -o ExitOnForwardFailure=yes \
    "''${rflags[@]}" \
    "$target" \
    "export HOST_TOOLS_MCP_SOCKETS='$remote_env'; exec \$SHELL -l"
}
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
		sandbox_restrictions = merged_restrictions // {
			dev = dev_allowlist;
			network = true;
			share_pid = true;
		};  # with network
	}).scripts;

	  	zsh_nonet_scripts = (import ../_wrapper/default.nix {
	  		name = "zsh-nonet";
		  		inherit pkgs bin;
		  		sandbox_restrictions = merged_restrictions // {
			  			dev = dev_allowlist;
			  			share_pid = true;
			  		};  # same fs/env as zsh, no network (no network key)
		  		generate_unsafe = false;
	  	}).scripts;
 in
 {
 	scripts = zsh_scripts ++ zsh_nonet_scripts;
	sandbox_restrictions = merged_restrictions // {
		dev = dev_allowlist;
	};
 }
