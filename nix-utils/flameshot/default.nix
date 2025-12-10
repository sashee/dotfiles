{
	pkgs,
}:
let
	bin = "${pkgs.flameshot}/bin/flameshot";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "rw";
			"~/.Xauthority" = "ro";
			"~/.config/flameshot" = "rw";
			"/run/user/1000/bus" = "rw";
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = false;
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/flameshot
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "flameshot";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
