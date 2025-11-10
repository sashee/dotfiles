{
	pkgs,
}:
let
	bins = (map (bin: pkgs.libreoffice + "/bin/" + bin) (builtins.attrNames (builtins.readDir (pkgs.libreoffice + "/bin"))));

	landrun_restrictions = {
		env = ["DISPLAY" "HOME" "PATH" "TMPDIR" "LANG" "TERM" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = {};
	};

	before = ''

	'';

	landrun_setup = ''

	'';

	scripts = builtins.concatLists (map (bin: (import ../wrapper.nix {
		name = builtins.baseNameOf bin;
		inherit pkgs landrun_restrictions before landrun_setup;
		bin = bin;
		restrict_to_current_folder = false;
	}).scripts) bins);
in
{
	inherit scripts landrun_restrictions;
}
