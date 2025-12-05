{
	pkgs,
}:
let
	bin =
		let
			config = pkgs.writeTextFile {
				name = "profile.conf";
				text = ''
noblacklist ~/.config/chromium
noblacklist ~/.config/Google

# keyd compose file (unicode characters)
whitelist /usr/share/keyd
noblacklist /usr/share/keyd/keyd.compose

noblacklist ~/.ssh/known_hosts
blacklist ~/.ssh/*
blacklist ~/*.kdbx
blacklist ~/**/*.kdbx
blacklist ~/.config/chromium
blacklist ~/.config/Google
blacklist ~/.config/keepassxc
blacklist ~/.config/syncthing
blacklist ~/.gnupg
blacklist ~/laptop-backup
blacklist ~/Mobile-backup
blacklist ~/safe

read-only ~/dotfiles
read-only ~/private_scripts

noblacklist ''${RUNUSER}/ssh-agent.socket
whitelist ''${RUNUSER}/ssh-agent.socket

env AWSKEYS=""

include ${pkgs.firejail}/etc/firejail/chromium.profile
			'';
		};
		in
		"firejail --profile=${config} ${pkgs.ungoogled-chromium}/bin/chromium";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"~/.config/chromium" = "rw";
			"~/.cache/chromium" = "rw";
			"~/.local/share/chromium" = "rw";
		};
		env = ["DISPLAY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XAUTHORITY" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = {};
	};
	before = "";

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/chromium
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/chromium
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/chromium
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "chromium";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}