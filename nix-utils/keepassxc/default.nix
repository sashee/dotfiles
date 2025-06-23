{}: (
import ../wrapper.nix {
	name = "keepassxc";
	get_landrun_requirements = {pkgs}: ''
			--unrestricted-filesystem \
			--env DISPLAY \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env SSH_AUTH_SOCK \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.keepassxc}/bin/keepassxc";
	restrict_to_current_folder = false;
}
)


