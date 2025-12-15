{
	pkgs,
}:
let
	bin = "${pkgs.sqlite}/bin/sqlite3";
	sandbox_restrictions = {
		env = ["TERM"];
		network = false;
	};
	before = ''
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "sqlite3";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}

