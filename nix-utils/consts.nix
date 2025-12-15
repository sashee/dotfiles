{
	SKIP_SANDBOX_ENV_VAR_NAME = "__NIX_UTILS_SKIP_SANDBOX";
	RESTRICT_TO_ENV_VAR_NAME = "__NIX_UTILS_RESTRICT_TO";
	protectedPaths = [
		# User data directories
		{ path = "~/.config/chromium"; type = "dir"; }
		{ path = "~/.config/syncthing"; type = "dir"; }
		# X11 display socket
		{ path = "/tmp/.X11-unix"; type = "dir"; }
		# High risk sockets
		{ path = "/run/docker.sock"; type = "file"; }
		{ path = "/run/user/1000/gnupg"; type = "dir"; }
		{ path = "/run/user/1000/bus"; type = "file"; }
		{ path = "/run/dbus/system_bus_socket"; type = "file"; }
		# Medium risk sockets
		{ path = "/run/libvirt"; type = "dir"; }
		{ path = "/run/user/1000/pipewire-0"; type = "file"; }
		{ path = "/run/user/1000/pipewire-0-manager"; type = "file"; }
		{ path = "/run/user/1000/pulse"; type = "dir"; }
		{ path = "/run/user/1000/p11-kit"; type = "dir"; }
	];
}
