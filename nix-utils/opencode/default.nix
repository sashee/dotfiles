{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
	pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

	config = pkgs.writeTextFile {
		name = "opencode.conf";
		text = ''
{
  "$schema": "https://opencode.ai/schema.json",
	"autoupdate": false,
	"share": "disabled",
	"permission": {
		"external_directory": {
			"/nix": "allow"
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
