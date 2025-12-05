{
	pkgs,
}:
let
	bin = "${pkgs.keepassxc}/bin/keepassxc";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"~/.Xauthority" = "ro";
			"~/.config/keepassxc" = "rw";
			"~/laptop-backup" = "rw";
			"~/safe" = "rw";
			"~/.cache/keepassxc" = "rw";
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = false;
		mount_dev = true;
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/keepassxc
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/keepassxc
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "keepassxc";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
