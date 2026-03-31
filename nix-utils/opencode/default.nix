{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
	pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

	agentsmd = pkgs.writeTextFile {
		name = "AGENTS.md";
		text = ''
# AGENTS.md

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
		'';
	};


	config = pkgs.writeTextFile {
		name = "opencode.json";
		text = ''
{
  "$schema": "https://opencode.ai/config.json",
	"autoupdate": false,
	"share": "disabled",
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
			"$HOME/.local/share/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.config/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/state/opencode" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/opencode" = { perm = "rw"; mkdir = true; };
		};
		network = true;
	};
	bin = launcher.mkLauncher {
		name = "opencode";
		target = "${pkgs2.opencode}/bin/opencode";
		keepEnv = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM" "OPENCODE_CONFIG"];
		setEnv = {
			OPENCODE_CONFIG = "${config}";
		};
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "opencode";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
