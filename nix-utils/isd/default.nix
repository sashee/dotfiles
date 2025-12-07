{
	pkgs,
}:
let
	bin = "${pkgs.isd}/bin/isd";
	sandbox_restrictions = {
		fs = {
			"~/.config/isd_tui" = "rw";
			"~/.local/share/isd_tui" = "rw";
			"~/.cache/isd_tui" = "rw";
			"/run/user/1000/bus" = "ro";
			"/run/dbus/system_bus_socket" = "ro";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "DBUS_SESSION_BUS_ADDRESS"];
		network = false;
	};
	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/isd_tui
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/isd_tui
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/isd_tui
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "isd";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
