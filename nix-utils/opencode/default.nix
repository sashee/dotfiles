{
	pkgs,
}:
let
	nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
	pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

	config = pkgs.writeTextFile {
		name = "opencode.conf";
		text = ''
{
  "$schema": "https://opencode.ai/schema.json",
	"autoupdate": false,
	"share": "disabled"
}
		'';
	};

	bin = "${pkgs2.opencode}/bin/opencode";
	sandbox_restrictions = {
		fs = {
			"~/.local/share/opencode" = "rw";
			"~/.config/opencode" = "rw";
			"~/.local/state/opencode" = "rw";
			"~/.cache/opencode" = "rw";
		};
		env = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM" "OPENCODE_CONFIG"];
		network = true;
	};
	before = ''
export OPENCODE_CONFIG=${config}
	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.local/state/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/opencode
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "opencode";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
