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
			"$HOME/.local/share/opencode" = "rw";
			"$HOME/.config/opencode" = "rw";
			"$HOME/.local/state/opencode" = "rw";
			"$HOME/.cache/opencode" = "rw";
		};
		env = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "LANG" "TERM" "OPENCODE_CONFIG"];
		network = true;
	};
	before = ''
export OPENCODE_CONFIG=${config}
	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/opencode
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/share/opencode
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/state/opencode
		${pkgs.coreutils}/bin/mkdir -p $HOME/.cache/opencode
	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "opencode";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
