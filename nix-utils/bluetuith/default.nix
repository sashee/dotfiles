{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	config = pkgs.runCommandLocal "config" {} ''
	mkdir -p $out/bluetuith
	touch $out/bluetuith/bluetuith.conf
	'';
	sandbox_restrictions = {
		fs = {
			"/run/user/1000/bus" = "ro";
			"/run/dbus/system_bus_socket" = "ro";
		};
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "bluetuith";
		target = "${pkgs.bluetuith}/bin/bluetuith";
		setEnv = {
			XDG_CONFIG_HOME = "${config}";
		};
	};
	before = ''
	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/bluetuith

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "bluetuith";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
