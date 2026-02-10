{
	pkgs,
}:
let
	bin = "${pkgs.lazysql}/bin/lazysql";
	sandbox_restrictions = {
		env = ["TERM" "HOME" "PATH"];
		network = false;
	};
	before = ''
export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.ncurses
	]
}"

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "lazysql";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
