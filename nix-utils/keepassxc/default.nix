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
			"$SSH_AUTH_SOCK" = "ro";
			"/run/user/1000/bus" = "ro";
			"/run/dbus/system_bus_socket" = "ro";
			"/run/udev" = "ro";
		};
		seccomp = {
			block = {
				AF_INET = true;
				AF_INET6 = true;
			};
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS"];
		network = true;  # Allow network namespace (for udev/netlink), but block inet via seccomp
		mount_dev = true;
		share_user = false;
		share_ipc = false;
		share_pid = false;
		share_cgroup = false;
		share_uts = false;
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
