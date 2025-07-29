{}:
import ../wrapper.nix {
	name = "duckdb";
	get_landrun_requirements = {pkgs}: ''
			--rox /nix,/proc,/sys \
			--rwx /dev/null \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env TERM \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.duckdb}/bin/duckdb";
}

