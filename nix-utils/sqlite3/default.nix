{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "sqlite3";
		target = "${pkgs.sqlite}/bin/sqlite3";
		keepEnv = ["TERM"];
	};
	before = ''
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "sqlite3";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
