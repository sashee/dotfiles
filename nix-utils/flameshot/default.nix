{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "rw"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.config/flameshot" = { perm = "rw"; mkdir = true; };
		};
		dbus = {
			"$XDG_RUNTIME_DIR/bus" = {
				own = ["org.flameshot.Flameshot"];
				log = true;
			};
		};
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "flameshot";
		target = "${pkgs.flameshot}/bin/flameshot";
		keepEnv = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS"];
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "flameshot";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
