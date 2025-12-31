{
	pkgs,
}:
let
	bin = "${pkgs.vlc}/bin/vlc --no-qt-privacy-ask";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"$HOME/.Xauthority" = "ro";
			"$HOME/.local/share/vlc" = "rw";
			"$HOME/.config/vlc" = "rw";
			"/run/user/1000/pipewire-0" = "ro";
			"/run/user/1000/pulse" = "ro";
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = false;
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/share/vlc
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/vlc
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "vlc";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
