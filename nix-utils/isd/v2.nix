{
	pkgs,
}:
let
	bin = "${pkgs.isd}/bin/isd";
	landrun_restrictions = {
		fs = {
			"/usr" = "rox";
			"/dev" = "rox";
			"/nix" = "rox";
			"/proc" = "rox";
			"/var" = "rox";
			"/run" = "rox";
			"/dev/null" = "rwx";
			"/dev/ptmx" = "rwx";
			"/dev/pts" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
			"/etc" = "ro";
			"~/.config/isd_tui" = "rwx";
			"~/.local/share/isd_tui" = "rwx";
			"~/.cache/isd_tui" = "rwx";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG"];
		network = {};
	};
	before = ''

	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/isd_tui
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/isd_tui
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/isd_tui
	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "isd";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
