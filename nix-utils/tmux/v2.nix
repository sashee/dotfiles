{
	zsh,
	pkgs,
}:
let
	config = pkgs.writeTextFile {
		name = "tmux.conf";
		text = ''
bind -n M-h select-pane -L
bind -n M-j select-pane -D
bind -n M-k select-pane -U
bind -n M-l select-pane -R

bind -n C-h previous-window
bind -n C-l next-window

set-option -g history-limit 50000

# Enable mouse mode (tmux 2.1 and above)
set -g mouse on

set -g status-interval 60

set-window-option -g mode-keys vi

bind-key -T copy-mode-vi 'v' send -X begin-selection
bind-key -T copy-mode-vi 'y' send -X copy-selection-and-cancel

set -sg escape-time 10

set-option -g default-shell ${builtins.elemAt zsh.scripts 0}/bin/zsh

set-option -g mouse off

set -as terminal-features ",$TERM:RGB"

set-option -ga update-environment ' AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN DISPLAY TZ'
		'';
	};

	bin = "${pkgs.tmux}/bin/tmux -f ${config}";

	before = ''

	'';

	landrun_setup = zsh.landrun_setup or ''

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "tmux";
		inherit pkgs bin;
		landrun_restrictions = zsh.landrun_restrictions;
		inherit before landrun_setup;
	}).scripts;
	inherit (zsh) landrun_restrictions;
}