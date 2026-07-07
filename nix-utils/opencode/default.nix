{
	pkgs,
	unstable,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	hostTools = import ./host-tools-mcp.nix { inherit pkgs; };
	inherit (hostTools) hostToolsMcp mcpRegisterBins brokerEnsureCmd;

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

	sandbox_restrictions = {
		fs = {
			"/tmp/host-tools-mcp" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.config/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/state/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/opencode" = { perm = "rw"; mkdir = true; };
		};
		network = true;
		dev = ["/dev/kvm"];
	};
	bin = launcher.mkLauncher {
		name = "opencode";
		target = "${unstable.opencode}/bin/opencode";
		keepEnv = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM" "OPENCODE_CONFIG"];
		setEnv = {
			OPENCODE_CONFIG = "${config}";
		};
	};
	wrapper = import ../_wrapper/default.nix {
		name = "opencode";
		inherit pkgs bin sandbox_restrictions;
		preLaunchHostCmd = brokerEnsureCmd;
	};
in
{
	scripts = wrapper.scripts ++ [ mcpRegisterBins ];
	inherit sandbox_restrictions;
}
