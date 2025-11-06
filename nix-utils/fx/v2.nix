{
	pkgs,
}:
let
	bin = "${pkgs.fx}/bin/fx";
	landrun_restrictions = {
		fs = {
			"/nix" = "rox";
			"/dev/null" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		};
		env = ["TERM" "HOME"];
		network = {};
	};
	before = ''

	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "fx";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
