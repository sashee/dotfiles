# Shared host-tools-mcp infrastructure: the Rust package (server + mcp-register +
# broker), the host-side register/broker bin set, and the broker auto-start cmd.
# Both the opencode and claude wrappers consume this so it lives in one place.
{ pkgs }:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	rustSrc = import ../rust-src.nix { inherit pkgs; };
	hostToolsMcp = pkgs.rustPlatform.buildRustPackage {
		pname = "host-tools-mcp";
		version = "0.1.0";
		src = rustSrc "opencode/host-tools-mcp";
		sourceRoot = "nix-utils/opencode/host-tools-mcp";
		cargoLock = {
			lockFile = ./host-tools-mcp/Cargo.lock;
		};
		doCheck = true;
	};
	# The broker runs through the same bwrap sandbox as every other program (no
	# special-casing): read-only root, no network, and writable only under the
	# tmpdir that holds its socket. It's a detached singleton, so it must outlive
	# the launching client (dont_die_with_parent) and isn't folder-scoped.
	brokerBin = launcher.mkLauncher {
		name = "host-tools-mcp-broker";
		target = "${hostToolsMcp}/bin/host-tools-mcp-broker";
		# Pass TMPDIR through (don't pin it): the in-sandbox broker must derive the
		# same ${TMPDIR:-/tmp}/host-tools-mcp/broker.sock as host-side mcp-register.
		keepEnv = [ "HOME" "PATH" "TMPDIR" ];
		setEnv = {};
	};
	brokerWrapper = import ../_wrapper/default.nix {
		name = "host-tools-mcp-broker";
		inherit pkgs;
		bin = brokerBin;
		sandbox_restrictions = {
			# Bind the host-tools-mcp dir rw (where the broker socket and the per-
			# server registry socks live) — same dir the clients bind, so the broker
			# socket is visible to every sandboxed consumer. Both entries cover
			# `${TMPDIR:-/tmp}/host-tools-mcp`: TMPDIR unset -> "$TMPDIR/..." is skipped
			# and "/tmp/..." applies; TMPDIR set -> "$TMPDIR/..." binds the real dir.
			fs = {
				"/tmp/host-tools-mcp" = { perm = "rw"; mkdir = true; };
				"$TMPDIR/host-tools-mcp" = { perm = "rw"; mkdir = true; };
			};
			network = false;
			dont_die_with_parent = true;
		};
		restrict_to_current_folder = false;
		generate_unsafe = false;
		quiet = true;
	};
	# The wrapper's main script (always first) is named host-tools-mcp-broker and
	# forwards "$@", so `host-tools-mcp-broker --ensure` reaches the binary.
	brokerBinPath = "${builtins.head brokerWrapper.scripts}/bin/host-tools-mcp-broker";

	# Connect helper: ssh to the rpi with the broker socket forwarded, creating the
	# nested socket dynamically (see ssh-rpi.sh). Plain on-PATH script, unsandboxed
	# like mcp-register (it needs the real ssh-agent, network, TTY and ~/.ssh).
	# dumbpipe is prepended to PATH for the ProxyCommand transport.
	sshRpi = pkgs.writeShellScriptBin "ssh-rpi" ''
		export PATH=${pkgs.lib.makeBinPath [ pkgs.dumbpipe ]}:"$PATH"
		${builtins.readFile ./ssh-rpi.sh}
	'';

	mcpRegisterBins = pkgs.runCommand "mcp-register-bins" {} ''
		mkdir -p "$out/bin"
		ln -s "${hostToolsMcp}/bin/mcp-register" "$out/bin/mcp-register"
		ln -s "${hostToolsMcp}/bin/mcp-register-prefix" "$out/bin/mcp-register-prefix"
		ln -s "${brokerBinPath}" "$out/bin/host-tools-mcp-broker"
		ln -s "${sshRpi}/bin/ssh-rpi" "$out/bin/ssh-rpi"
	'';

	# Host-side (pre-sandbox) auto-start of the sandboxed multiplexing broker:
	# detached via setsid so it outlives this launch; `--ensure` is a fast no-op if
	# one is already running. The broker idle-exits when no clients remain.
	brokerEnsureCmd = "${pkgs.util-linux}/bin/setsid -f ${brokerBinPath} --ensure >/dev/null 2>&1 || true";
in
{
	inherit hostToolsMcp mcpRegisterBins brokerEnsureCmd;
}
