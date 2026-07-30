# The host-tools-mcp infrastructure, as a program in its own right: the Rust package
# (server + mcp-register + broker), the host-side register/broker bin set, and the
# broker auto-start cmd.
#
# This is deliberately NOT part of opencode/claude, even though they're its main
# consumers. mcp-register/-prefix are the registration channel into a remote box: you
# ssh in and register host commands as MCP tools. A headless box therefore needs these
# CLIs but has no use for an agent, and while these bins rode on opencode's `scripts`
# it had to install opencode to get them (see hosts/rpi5 in the nixos-test repo).
#
# ./crate holds the Rust sources one level down rather than beside this file: rustSrc
# copies the whole crate path, so a flat layout would make every edit here invalidate a
# Rust build that runs the full test suite (doCheck) — expensive on the aarch64 CI job.
{ pkgs }:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	rustSrc = import ../rust-src.nix { inherit pkgs; };
	hostToolsMcp = pkgs.rustPlatform.buildRustPackage {
		pname = "host-tools-mcp";
		version = "0.1.0";
		src = rustSrc "host-tools-mcp/crate";
		sourceRoot = "nix-utils/host-tools-mcp/crate";
		cargoLock = {
			lockFile = ./crate/Cargo.lock;
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
		# HOST_TOOLS_MCP_BROKER_IDLE_MS is an optional idle-grace override, normally
		# unset (broker falls back to its 30s default); passed through only so tests
		# can hold the broker open while a slow client starts.
		keepEnv = [ "HOME" "PATH" "TMPDIR" "HOST_TOOLS_MCP_BROKER_IDLE_MS" ];
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
	# The bins this program contributes to the env: mcp-register, mcp-register-prefix,
	# host-tools-mcp-broker, ssh-rpi. Previously appended to opencode's and claude's
	# scripts, which is what tied the registration CLIs to having an agent installed.
	scripts = [ mcpRegisterBins ];

	# These bins are unsandboxed (they need the real ssh-agent, network and ~/.ssh), so
	# this isn't the sandbox they run in — it's what zsh/default.nix merges into the
	# LOGIN SHELL's sandbox. mcp-register derives its socket path from
	# ${TMPDIR:-/tmp}/host-tools-mcp, so both spellings must be writable inside the
	# sandboxed shell or a register run from that shell can't reach the broker. Until
	# this program existed, that binding reached zsh only via opencode/claude, so
	# skipping them would have left the CLI on PATH but unable to connect. Mirrors the
	# brokerWrapper rules above; "$TMPDIR/..." is skipped when TMPDIR is unset.
	sandbox_restrictions = {
		fs = {
			"/tmp/host-tools-mcp" = { perm = "rw"; mkdir = true; };
			"$TMPDIR/host-tools-mcp" = { perm = "rw"; mkdir = true; };
		};
	};

	inherit hostToolsMcp mcpRegisterBins brokerEnsureCmd;
}
