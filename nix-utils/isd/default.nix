{
	pkgs,
}:
let
	bin = "${pkgs.isd}/bin/isd";
	sandbox_restrictions = {
		fs = {
			"~/.config/isd_tui" = "rw";
			"~/.local/share/isd_tui" = "rw";
			"~/.cache/isd_tui" = "rw";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG"];
		network = {};
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/isd_tui
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/isd_tui
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/isd_tui
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "isd";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
