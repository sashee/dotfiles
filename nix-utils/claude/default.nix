{
	pkgs,
	unstable,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	rustSrc = import ../rust-src.nix { inherit pkgs; };
		hostToolsMcp = pkgs.rustPlatform.buildRustPackage {
			pname = "host-tools-mcp";
			version = "0.1.0";
			src = rustSrc "opencode/host-tools-mcp";
			sourceRoot = "nix-utils/opencode/host-tools-mcp";
			cargoLock = {
				lockFile = ../opencode/host-tools-mcp/Cargo.lock;
			};
			doCheck = true;
		};
	mcpRegisterBins = pkgs.runCommand "mcp-register-bins" {} ''
		mkdir -p "$out/bin"
		ln -s "${hostToolsMcp}/bin/mcp-register" "$out/bin/mcp-register"
		ln -s "${hostToolsMcp}/bin/mcp-register-prefix" "$out/bin/mcp-register-prefix"
	'';

	claudemd = pkgs.writeTextFile {
		name = "CLAUDE.md";
		text = ''
# CLAUDE.md

## Core Principles
- Prefer pure functions when practical.
- Avoid mutation unless it is clearly necessary for performance or API constraints.
- Minimize state; compute derived values instead of storing redundant data.
- Keep side effects at the edges of the system.
- Favor simple data transformations over complex control flow.

## State Management
- Do not introduce mutable shared state unless there is no reasonable alternative.
- Prefer passing data through function arguments and return values.
- Keep state local, short-lived, and explicit.
- If state must exist, store the smallest possible source of truth.

## Code Style
- Prefer declarative code over imperative code.
- Break logic into small composable functions.
- Avoid hidden dependencies and implicit inputs.
- Prefer data-in/data-out helpers over class-like stateful abstractions.
- When coding in Rust, try to avoid usafe blocks if possible

## Mutations
- Do not mutate arrays, objects, maps, or sets in place if a non-mutating approach is reasonable.
- Prefer `map`, `filter`, `reduce`, object spread, and new values over reassignment.
- If mutation is necessary, keep it tightly scoped and explain why.

## Responses
- Be concise.
- Do not be verbose or repetitive.
- Give direct answers first; add detail only when it improves clarity.
- Prefer bullet points over long paragraphs.
Best practices when writing it:
- Use “prefer” for defaults, “do not” for strong rules, “must” only for hard constraints.
- Include exceptions so the rules do not become brittle.
- Keep each bullet to one idea.
- Favor behavior the agent can verify from code.
- Include 1–2 good examples and 1 bad example if you want stronger adherence.
A useful refinement is to define exceptions explicitly:

## Exceptions
- Mutation is acceptable when required by a library API, interoperability needs, or demonstrated performance constraints.
- In those cases, keep mutation local and avoid exposing mutated shared state.

## Sandboxing

- You are running in a sandbox so you won't have access to the full system.
		'';
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
	};
in
{
	scripts = wrapper.scripts ++ [ mcpRegisterBins ];
	inherit sandbox_restrictions;
}
