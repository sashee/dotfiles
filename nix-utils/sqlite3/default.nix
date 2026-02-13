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
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "sqlite3";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
