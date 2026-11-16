{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.config/keepassxc" = { perm = "rw"; mkdir = true; };
			"$HOME/laptop-backup" = { perm = "rw"; };
			"$HOME/safe" = { perm = "rw"; };
			# 2.8+ keeps recent/last-opened DBs in $XDG_STATE_HOME/keepassxc/keepassxc_local.ini
			# (was ~/.cache/keepassxc/keepassxc.ini); XDG_STATE_HOME isn't in keepEnv, so the default applies.
			"$HOME/.local/state/keepassxc" = { perm = "rw"; mkdir = true; };
			"$SSH_AUTH_SOCK" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/bus" = { perm = "ro"; };
			"/run/udev" = { perm = "ro"; };
		};
		seccomp = {
			block = {
				AF_INET = true;
				AF_INET6 = true;
			};
		};
		network = true;  # Allow network namespace (for udev/netlink), but block inet via seccomp
		dev = true;
		share_user = false;
		share_ipc = false;
		share_pid = false;
		share_cgroup = false;
		share_uts = false;
	};
	bin = launcher.mkLauncher {
		name = "keepassxc";
		target = "${pkgs.keepassxc}/bin/keepassxc";
		keepEnv = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS"];
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "keepassxc";
		inherit pkgs bin sandbox_restrictions;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
