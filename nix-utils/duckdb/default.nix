{
	pkgs,
}:
let
	bin =
		let
			config = pkgs.writeTextFile {
				name = "duckdbrc";
				text = ''
				'';
			};
		in
		"${pkgs.duckdb}/bin/duckdb -init ${config}";
	sandbox_restrictions = {
		env = ["TERM" "DUCKDB_HISTORY"];
		network = false;
	};
	before = ''
export DUCKDB_HISTORY=/tmp/.duckdb_history
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "duckdb";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
