{
	pkgs,
	nvim,
}:
let
	bin = "${pkgs.isd}/bin/isd";
	sandbox_restrictions = {
		fs = {
			"$HOME/.config/isd_tui" = "rw";
			"$HOME/.local/share/isd_tui" = "rw";
			"$HOME/.cache/isd_tui" = "rw";
			"/run/user/1000/bus" = "ro";
			"/run/dbus/system_bus_socket" = "ro";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "DBUS_SESSION_BUS_ADDRESS" "VISUAL" "EDITOR"];
		network = false;
	};
	before = ''
	export VISUAL="${builtins.elemAt nvim.scripts 0}/bin/nvim"
	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/isd_tui
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/share/isd_tui
		${pkgs.coreutils}/bin/mkdir -p $HOME/.cache/isd_tui
	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "isd";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
