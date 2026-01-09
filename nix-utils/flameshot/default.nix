{
	pkgs,
}:
let
	bin = "${pkgs.flameshot}/bin/flameshot";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "rw";
			"$HOME/.Xauthority" = "ro";
			"$HOME/.config/flameshot" = "rw";
		};
		dbus = {
			"/run/user/1000/bus" = {
				own = ["org.flameshot.Flameshot"];
				log = true;
			};
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS"];
		network = false;
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/flameshot
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "flameshot";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
