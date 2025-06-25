{pkgs}:
let
	bins = (map (bin: pkgs.libreoffice + "/bin/" + bin) (builtins.attrNames (builtins.readDir (pkgs.libreoffice + "/bin"))));

	get_landrun_requirements = {pkgs}: ''
			--env DISPLAY \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env LANG \
			--env TERM \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--unrestricted-filesystem \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	wrapper = import ../wrapper.nix;
in
	(map (bin: (wrapper {
		name = builtins.baseNameOf bin;
		inherit get_landrun_requirements get_landrun_setup get_before;
		get_bin = {pkgs}: bin;
		restrict_to_current_folder = false;
	})) bins)
