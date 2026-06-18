{
	SKIP_SANDBOX_ENV_VAR_NAME = "__NIX_UTILS_SKIP_SANDBOX";
	RESTRICT_TO_ENV_VAR_NAME = "__NIX_UTILS_RESTRICT_TO";
	# Env vars allowed to be unset: a mount path referencing one of these is
	# skipped when the var is missing (headless = no WAYLAND_DISPLAY, no
	# ssh-agent = no SSH_AUTH_SOCK). Every other referenced var is required and
	# errors if unset.
	optionalEnvVars = [ "WAYLAND_DISPLAY" "SSH_AUTH_SOCK" ];
	# The /dev nodes `bwrap --dev /dev` creates (fixed per bubblewrap version). For
	# dev-allowlist tools the runner keeps these (never block-mounts them) while
	# blocking other real devices. Kept as a constant instead of probing bwrap on
	# every launch; tests/cases/dev-baseline.nix guards it against bwrap drift.
	fakeDevEntries = [
		"core" "fd" "full" "null" "ptmx" "pts" "random" "shm"
		"stderr" "stdin" "stdout" "tty" "urandom" "zero"
	];
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
		# systemd --user manager control sockets (private + io.systemd.Manager
		# varlink). These speak D-Bus/varlink as a direct peer, bypassing the
		# session bus, so blocking `bus` above is not enough: a sandboxed process
		# could StartTransientUnit and spawn outside the sandbox. Block the whole
		# dir so all sockets under it (private, io.systemd.Manager, notify) go away.
		{ path = "$XDG_RUNTIME_DIR/systemd"; type = "dir"; }
		{ path = "/run/dbus/system_bus_socket"; type = "file"; }
		{ path = "/etc/ssh/ssh_config.d"; type = "dir"; }
		# Medium risk sockets
		{ path = "/run/libvirt"; type = "dir"; }
		{ path = "$XDG_RUNTIME_DIR/pipewire-0"; type = "file"; }
		{ path = "$XDG_RUNTIME_DIR/pipewire-0-manager"; type = "file"; }
		{ path = "$XDG_RUNTIME_DIR/pulse"; type = "dir"; }
		{ path = "$XDG_RUNTIME_DIR/p11-kit"; type = "dir"; }
		# LibreOffice's private D-Bus dir (its own UNO/soffice IPC socket, not the
		# host bus). Blocked by default so another sandbox can't drive a running
		# LibreOffice (which has broad $HOME access); LibreOffice opts back in via
		# its own fs entry.
		{ path = "$XDG_RUNTIME_DIR/libreoffice-dbus"; type = "dir"; }
		# Systemd journal (persistent + volatile). Readable by uid 1000 via ACL and
		# can hold logged secrets + the machine's full activity history. Blocked so
		# networked sandboxed tools can't read/exfil it; zsh (-> tmux/zellij) and
		# isd opt back in via their own fs entries.
		{ path = "/var/log/journal"; type = "dir"; }
		{ path = "/run/log/journal"; type = "dir"; }
		# zellij's session control socket lives in the shared runtime dir; any
		# sandbox that can reach it can drive the running session (zellij run /
		# action / write) to execute commands in zellij's (broad) sandbox. Block
		# it by default; zellij opts back in via its own fs entry.
		{ path = "$XDG_RUNTIME_DIR/zellij"; type = "dir"; }
	];
}
