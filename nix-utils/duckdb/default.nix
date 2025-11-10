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
	landrun_restrictions = {
		fs = {
			"/nix" = "rox";
			"/proc" = "rox";
			"/sys" = "rox";
			"/dev/null" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		};
		env = ["TERM" "DUCKDB_HISTORY"];
		network = {};
	};
	before = ''
export DUCKDB_HISTORY=/tmp/.duckdb_history
	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "duckdb";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
