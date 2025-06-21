{}: (
import ../wrapper.nix {
	name = "vlc";
	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix \
			--rwx /dev/null \
			--rwx $HOME/.local/share/vlc \
			--rwx $HOME/.config/vlc \
			--ro ~/.Xauthority \
			--env DISPLAY \
			--rwx "''${TMPDIR:-/tmp}" \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.vlc}/bin/vlc";
}
)

