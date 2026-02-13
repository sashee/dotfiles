{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	config = pkgs.writeTextFile {
		name = "duckdbrc";
		text = ''
		'';
	};
	sandbox_restrictions = {
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "duckdb";
		target = "${pkgs.duckdb}/bin/duckdb";
		keepEnv = ["TERM" "DUCKDB_HISTORY"];
		setEnv = {
			DUCKDB_HISTORY = "/tmp/.duckdb_history";
		};
		extraArgs = [ "-init" "${config}" ];
	};
	before = ''
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "duckdb";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
