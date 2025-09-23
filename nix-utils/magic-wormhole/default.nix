{}:
import ../wrapper.nix {
	name = "wormhole";
	get_landrun_requirements = {pkgs}: ''
			--rox /nix,/dev,/usr,/proc,/sys,/etc,/run/systemd/resolve \
			--rwx /dev/null \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env TERM \
			--unrestricted-network \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.magic-wormhole}/bin/wormhole";
}




