{
	pkgs,
	nvim,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"$HOME/.config/isd_tui" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/isd_tui" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/isd_tui" = { perm = "rw"; mkdir = true; };
			"$XDG_RUNTIME_DIR/bus" = { perm = "ro"; };
			"/run/dbus/system_bus_socket" = { perm = "ro"; };
		};
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "isd";
		target = "${pkgs.isd}/bin/isd";
		keepEnv = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS" "VISUAL" "EDITOR"];
		setEnv = {
			VISUAL = "${builtins.elemAt nvim.scripts 0}/bin/nvim";
		};
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "isd";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
