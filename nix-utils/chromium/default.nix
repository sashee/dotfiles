{}:
import ../wrapper.nix {
	name = "chromium";
	get_landrun_requirements = {pkgs}: ''
			--unrestricted-filesystem \
			--unrestricted-network \
			--env HOME \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: "";

	get_bin = {pkgs}: 
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
	restrict_to_current_folder = false;
}



