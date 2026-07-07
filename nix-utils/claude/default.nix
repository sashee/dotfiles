{
	pkgs,
	unstable,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	hostTools = import ../opencode/host-tools-mcp.nix { inherit pkgs; };
	inherit (hostTools) hostToolsMcp mcpRegisterBins brokerEnsureCmd;

	claudemd = pkgs.writeTextFile {
		name = "CLAUDE.md";
		text = builtins.readFile ../opencode/AGENTS.md;
	};

	settingsJson = pkgs.writeTextFile {
		name = "settings.json";
		text = builtins.toJSON {
			"$schema" = "https://json.schemastore.org/claude-code-settings.json";
			env = {
				DISABLE_AUTOUPDATER = "1";
				CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
			};
			permissions = {
				defaultMode = "bypassPermissions";    # mirror opencode's allow-all (sandboxed anyway)
				allow = [ ];
				deny = [ ];
				# external_directory."*" = "allow"  ->  grant the dirs explicitly:
				additionalDirectories = [ "/" ];  # mirror your "*": "allow"; narrow this if you can
			};
		};
	};

	# The "mcp" block from opencode.json lives in its own file for --mcp-config.
	# opencode's command:["bin"] splits into command (string) + args (array).
	mcpJson = pkgs.writeTextFile {
		name = "mcp.json";
		text = builtins.toJSON {
			mcpServers = {
				"host-tools-mcp" = {
					type = "stdio";
					command = "${hostToolsMcp}/bin/host-tools-mcp";
					args = [ ];
				};
			};
		};
	};

	# Claude Code has no single OPENCODE_CONFIG-style env var, so inject via flags.
	# This thin entrypoint is what the launcher/sandbox wraps.
	claudeEntry = pkgs.writeShellScriptBin "claude" ''
		export CLAUDE_CONFIG_DIR="$HOME/.config/claude"
		export DISABLE_AUTOUPDATER="1"
		exec ${unstable.claude-code}/bin/claude \
			--settings ${settingsJson} \
			--mcp-config ${mcpJson} \
			--strict-mcp-config \
			--append-system-prompt "$(cat ${claudemd})" \
			"$@"
	'';

	sandbox_restrictions = {
		fs = {
			"/tmp/host-tools-mcp" = { perm = "rw"; mkdir = true; };
			"$HOME/.config/claude" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/claude" = { perm = "rw"; mkdir = true; };
		};
		network = true;
		dev = ["/dev/kvm"];
	};
	bin = launcher.mkLauncher {
		name = "claude";
		target = "${claudeEntry}/bin/claude";
		keepEnv = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM"];
		setEnv = {};
	};
	wrapper = import ../_wrapper/default.nix {
		name = "claude";
		inherit pkgs bin sandbox_restrictions;
		preLaunchHostCmd = brokerEnsureCmd;
	};
in
{
	scripts = wrapper.scripts ++ [ mcpRegisterBins ];
	inherit sandbox_restrictions;
}
