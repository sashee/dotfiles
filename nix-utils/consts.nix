{
	SKIP_SANDBOX_ENV_VAR_NAME = "__NIX_UTILS_SKIP_SANDBOX";
	RESTRICT_TO_ENV_VAR_NAME = "__NIX_UTILS_RESTRICT_TO";
	# Env vars allowed to be unset: a mount path referencing one of these is
	# skipped when the var is missing (headless = no WAYLAND_DISPLAY, no
	# ssh-agent = no SSH_AUTH_SOCK). Every other referenced var is required and
	# errors if unset.
	optionalEnvVars = [ "WAYLAND_DISPLAY" "SSH_AUTH_SOCK" ];
	protectedPaths = [
		# User data directories
		# Block all of ~/.config by default; tools opt back in to specific
		# subdirs via sandbox_restrictions.fs (allowlist, not denylist).
		{ path = "$HOME/.config"; type = "dir"; }
		{ path = "$HOME/.local/share/opencode"; type = "dir"; }
		# X11 display socket
		{ path = "/tmp/.X11-unix"; type = "dir"; }
		# Wayland display socket
		{ path = "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"; type = "file"; }
		# High risk sockets
		{ path = "/run/docker.sock"; type = "file"; }
		{ path = "$XDG_RUNTIME_DIR/gnupg"; type = "dir"; }
		{ path = "$XDG_RUNTIME_DIR/bus"; type = "file"; }
		{ path = "/run/dbus/system_bus_socket"; type = "file"; }
		{ path = "/etc/ssh/ssh_config.d"; type = "dir"; }
		# Medium risk sockets
		{ path = "/run/libvirt"; type = "dir"; }
		{ path = "$XDG_RUNTIME_DIR/pipewire-0"; type = "file"; }
		{ path = "$XDG_RUNTIME_DIR/pipewire-0-manager"; type = "file"; }
		{ path = "$XDG_RUNTIME_DIR/pulse"; type = "dir"; }
		{ path = "$XDG_RUNTIME_DIR/p11-kit"; type = "dir"; }
	];
}
