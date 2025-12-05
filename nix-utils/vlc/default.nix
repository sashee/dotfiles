{
	pkgs,
}:
let
	bin = "${pkgs.vlc}/bin/vlc";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"~/.Xauthority" = "ro";
			"~/.local/share/vlc" = "rw";
			"~/.config/vlc" = "rw";
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = false;
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
