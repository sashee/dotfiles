{
	pkgs,
}:
let
	bin = "${pkgs.flameshot}/bin/flameshot";
	landrun_restrictions = {
		fs = {
			"/nix" = "rox";
			"/proc" = "rox";
			"/sys" = "rox";
			"/dev/null" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		};
		network = {};
	};
	before = ''

	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "flameshot";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
