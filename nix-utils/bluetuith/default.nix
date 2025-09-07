{}:
import ../wrapper.nix {
	name = "bluetuith";
	get_landrun_requirements = {pkgs}: ''
			--rox /nix,/proc,/sys \
			--rwx /dev/null \
			--unrestricted-filesystem \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env TERM \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: 
	let
		config = pkgs.runCommandLocal "config" {} ''
		mkdir -p $out/bluetuith
		touch $out/bluetuith/bluetuith.conf
		'';
	in
	''
	export XDG_CONFIG_HOME=${config}
	'';

	get_bin = {pkgs}: 
	let
	in
	"${pkgs.bluetuith}/bin/bluetuith";
}


