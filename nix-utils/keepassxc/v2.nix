{
	pkgs,
}:
let
	bin = "${pkgs.keepassxc}/bin/keepassxc";
	landrun_restrictions = {
		env = ["DISPLAY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = {};
	};
	before = ''

	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "keepassxc";
		inherit pkgs bin landrun_restrictions before landrun_setup;
		restrict_to_current_folder = false;
	}).scripts;
	inherit landrun_restrictions;
}
