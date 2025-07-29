{}:
import ../wrapper.nix {
	name = "harlequin";
	get_landrun_requirements = {pkgs}: ''
			--rox /nix,/dev,/usr,/proc,/sys,/etc \
			--rwx /dev/null \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env TERM \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.harlequin}/bin/harlequin";
}


