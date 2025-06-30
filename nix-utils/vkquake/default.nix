{}: (
import ../wrapper.nix {
	name = "vkquake";
	get_landrun_requirements = {pkgs}: ''
			--rwx /usr,/dev,/nix,/etc,/run,/proc,/sys,/var \
			--rwx /dev/null \
			--ro ~/.config/dconf \
			--ro ~/.Xauthority \
			--env DISPLAY \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--env DBUS_SESSION_BUS_ADDRESS \
			--env WINDOWID \
			--env XDG_SEAT \
			--env WINDOWPATH \
			--env XDG_VTNR \
			--env XDG_SESSION_ID \
			--rwx ~/.vkquake \
			--rwx ~/.cache \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.coreutils}/bin/mkdir -p ~/.vkquake
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.vkquake}/bin/vkquake";
}
)


