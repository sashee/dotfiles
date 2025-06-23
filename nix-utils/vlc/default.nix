{}: (
import ../wrapper.nix {
	name = "vlc";
	get_landrun_requirements = {pkgs}: ''
			--rwx /usr,/dev,/nix,/etc,/run,/proc,/sys \
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
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/vlc
		${pkgs.coreutils}/bin/mkdir -p ~/.config/vlc
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.vlc}/bin/vlc";
}
)

