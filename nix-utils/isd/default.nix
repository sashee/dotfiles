{}: (
import ../wrapper.nix {
	name = "isd";
	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix,/proc,/var,/run \
			--rwx /dev/null \
			--rwx /dev/ptmx \
			--rwx /dev/pts \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--ro /etc \
			--rwx ~/.config/isd_tui \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/isd_tui
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.isd}/bin/isd";
}
)

