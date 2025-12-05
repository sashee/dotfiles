{
	pkgs,
}:
let
	bin = "${pkgs.keepassxc}/bin/keepassxc";
	sandbox_restrictions = {
		env = ["DISPLAY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = {};
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "keepassxc";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
