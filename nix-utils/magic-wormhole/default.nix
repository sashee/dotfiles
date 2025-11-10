{
	pkgs,
}:
let
	bin = "${pkgs.magic-wormhole}/bin/wormhole";
	landrun_restrictions = {
		fs = {
			"/nix" = "rox";
			"/dev" = "rox";
			"/usr" = "rox";
			"/proc" = "rox";
			"/sys" = "rox";
			"/etc" = "rox";
			"/run/systemd/resolve" = "rox";
			"/dev/null" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		};
		env = ["TERM"];
	};
	before = ''

	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "wormhole";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}