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
	# Unix sockets a sandboxed tool is permitted to connect to. Everything else
	# under the runtime dirs must be blocked (protectedPaths) or permission-denied;
	# tests/cases/uds-connectable.nix fails if a sandboxed tool can connect() to a
	# socket that isn't on this list (→ block it, or add it here after deciding it's
	# safe to expose). Both current entries are benign: nscd's name-service cache and
	# dhcpcd's unprivileged query socket.
	allowedSockets = [
		"/run/nscd/socket"
		"/run/dhcpcd/unpriv.sock"
	];
	# Abstract-namespace unix sockets a sandboxed tool is permitted to reach. These
	# have NO filesystem path, so protectedPaths can't block them; they're isolated
	# only by the network namespace, so network=false tools (--unshare-net) can't see
	# them, but network=true tools share the host netns and can. tests/cases/
	# abstract-sockets.nix fails if a sandboxed tool can reach a *listening* abstract
	# socket not on this list (e.g. an X server's @/tmp/.X11-unix/X0). Empty so far.
	allowedAbstractSockets = [ ];
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
		# systemd *system* manager runtime dir. Its io.systemd.* varlink sockets
		# (incl. io.systemd.Manager), journald-ingestion, notify and AskPassword are
		# mode 0666 and reachable by a sandboxed uid (recon: connectable on both a
		# minimal NixOS box and a desktop). The actual escape socket
		# (/run/systemd/private) is root-only and the system bus is blocked above, so
		# this is defense-in-depth (recon / info-disclosure surface). Nothing here is
		# needed by sandboxed tools (they reach systemd via the system bus, opted in
		# per tool). Requires no systemd-resolved (DNS via dnscrypt-proxy), so the
		# whole dir can go. Guarded by tests/cases/uds-connectable.nix.
		{ path = "/run/systemd"; type = "dir"; }
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
