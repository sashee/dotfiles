{
	pkgs,
	unstable,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	hostTools = import ./host-tools-mcp.nix { inherit pkgs; };
	inherit (hostTools) hostToolsMcp mcpRegisterBins brokerEnsureCmd;
	egressProxy = import ../egress-proxy/default.nix { inherit pkgs; };

	agentsmd = pkgs.writeTextFile {
		name = "AGENTS.md";
		text = builtins.readFile ./AGENTS.md;
	};

	config = pkgs.writeTextFile {
		name = "opencode.json";
		text = ''
{
  "$schema": "https://opencode.ai/config.json",
	"autoupdate": false,
	"share": "disabled",
	"mcp": {
		"host-tools-mcp": {
			"type": "local",
			"command": ["${hostToolsMcp}/bin/host-tools-mcp"],
			"enabled": true
		}
	},
	"instructions": ["${agentsmd}"],
	"permission": {
		"external_directory": {
			"*": "allow"
		}
	}
}
		'';
	};

	# Thin entrypoint (opencode has no relay hook of its own): start the in-sandbox
	# proxy relay, then exec the real binary. This is what the launcher/sandbox wraps.
	opencodeEntry = pkgs.writeShellScriptBin "opencode" ''
		${egressProxy.mkRelayPrelude}
		exec ${unstable.opencode}/bin/opencode "$@"
	'';

	sandbox_restrictions = {
		fs = {
			"/tmp/host-tools-mcp" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.config/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/state/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/opencode" = { perm = "rw"; mkdir = true; };
		} // egressProxy.fsEntry // egressProxy.caFsEntry;
		# Internet only via the HTTP egress proxy (see ../egress-proxy): isolated
		# netns, loopback-only, all traffic through HTTP(S)_PROXY. Fail-closed.
		network = "proxy";
		dev = ["/dev/kvm"];
	};
	bin = launcher.mkLauncher {
		name = "opencode";
		target = "${opencodeEntry}/bin/opencode";
		keepEnv = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM" "OPENCODE_CONFIG"] ++ egressProxy.proxyEnvNames ++ egressProxy.certEnvNames;
		setEnv = {
			OPENCODE_CONFIG = "${config}";
		} // egressProxy.proxyEnv // egressProxy.certEnv;
	};
	wrapper = import ../_wrapper/default.nix {
		name = "opencode";
		inherit pkgs bin sandbox_restrictions;
		preLaunchHostCmd = brokerEnsureCmd + "\n" + egressProxy.proxyEnsureCmd;
	};
in
{
	scripts = wrapper.scripts ++ [ mcpRegisterBins ];
	inherit sandbox_restrictions;
}
