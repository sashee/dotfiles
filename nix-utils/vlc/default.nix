{
	pkgs,
}:
let
	bin = "${pkgs.vlc}/bin/vlc";
	landrun_restrictions = {
		fs = {
			"/usr" = "rwx";
			"/dev" = "rwx";
			"/nix" = "rwx";
			"/etc" = "rwx";
			"/run" = "rwx";
			"/proc" = "rwx";
			"/sys" = "rwx";
			"/dev/null" = "rwx";
			"~/.local/share/vlc" = "rwx";
			"~/.config/vlc" = "rwx";
			"~/.Xauthority" = "ro";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
		};
		env = ["DISPLAY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = {};
	};
	before = ''

	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/vlc
		${pkgs.coreutils}/bin/mkdir -p ~/.config/vlc
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "vlc";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
