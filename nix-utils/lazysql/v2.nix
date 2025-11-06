{
	pkgs,
}:
let
	bin = "${pkgs.lazysql}/bin/lazysql";
	landrun_restrictions = {
		fs = {
			"/nix" = "rox";
			"/dev" = "rox";
			"/usr" = "rox";
			"/proc" = "rox";
			"/sys" = "rox";
			"/etc" = "rox";
			"/dev/null" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		};
		env = ["TERM" "HOME" "PATH"];
		network = {};
	};
	before = ''
export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.ncurses
	]
}"

	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "lazysql";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
