{}:
import ../wrapper.nix {
	name = "duckdb";
	get_landrun_requirements = {pkgs}: ''
			--rox /nix,/proc,/sys \
			--rwx /dev/null \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env TERM \
			--env DUCKDB_HISTORY \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
export DUCKDB_HISTORY=/tmp/.duckdb_history
	'';

	get_bin = {pkgs}: 
	let
		config = pkgs.writeTextFile {
			name = "duckdbrc";
			text = ''
			'';
		};
	in
	"${pkgs.duckdb}/bin/duckdb -init ${config}";
}

