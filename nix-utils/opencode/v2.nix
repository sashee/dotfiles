{
	pkgs,
}:
let
	nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
	pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

	config = pkgs2.writeTextFile {
		name = "opencode.conf";
		text = ''
{
  "$schema": "https://opencode.ai/schema.json",
  "provider": {
    "openrouter": {
			"model": {
				"gemini": {
					"provider": "openrouter",
					"model": "google/gemini-pro"
				}
			}
    }
  }
}
		'';
	};

	bin = "/usr/bin/opencode";
	landrun_restrictions = {
		fs = {
			"/usr" = "rox";
			"/dev" = "rox";
			"/nix" = "rox";
			"/run/systemd/resolve" = "rox";
			"/proc" = "rox";
			"~/.local/share/opencode" = "rwx";
			"~/.config/opencode" = "rwx";
			"~/.local/state/opencode" = "rwx";
			"~/.cache/opencode" = "rwx";
			"/dev/null" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
			"/etc/ssl" = "ro";
		};
		env = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM" "OPENCODE_CONFIG"];
	};
	before = ''
export OPENCODE_CONFIG=${config}
	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.local/state/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/opencode
	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "opencode";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
