{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.XCompose" = { perm = "ro"; };
			"$HOME/.config/torbrowser" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/torbrowser" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/torbrowser" = { perm = "rw"; mkdir = true; };
		};
		network = true;
		dev = true;
		share_user = true;
	};
	bin = launcher.mkLauncher {
		name = "tor-browser";
		target = "${pkgs.tor-browser}/bin/tor-browser";
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "tor-browser";
		inherit pkgs bin sandbox_restrictions;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
