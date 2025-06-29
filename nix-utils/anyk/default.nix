{}: (
import ../wrapper.nix {
	name = "anyk";
	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix,/etc \
			--rwx /usr/share/abevjava \
			--rwx /dev/null \
			--rwx ~/.abevjava \
			--rwx ~/abevjava \
			--ro ~/.Xauthority \
			--env DISPLAY \
			--rwx "''${TMPDIR:-/tmp}" \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--connect-tcp 443 \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.anyk}/bin/anyk";
	restrict_to_current_folder = false;
}
)

