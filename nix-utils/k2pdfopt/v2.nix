{
	pkgs,
}:
let
	bin = "${pkgs.k2pdfopt}/bin/k2pdfopt";
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
		env = ["TERM"];
		network = {};
	};
	before = ''

	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "k2pdfopt";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
