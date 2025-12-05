{
	pkgs,
}:
let
	bin = "${pkgs.vlc}/bin/vlc";
	sandbox_restrictions = {
		fs = {
			"~/.local/share/vlc" = "rw";
			"~/.config/vlc" = "rw";
			"~/.Xauthority" = "ro";
		};
		env = ["DISPLAY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = {};
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/vlc
		${pkgs.coreutils}/bin/mkdir -p ~/.config/vlc
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "vlc";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
