{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.XCompose" = { perm = "ro"; };
			"$HOME/.config/chromium" = { perm = "rw"; mkdir = true; };
			"$HOME/Downloads" = { perm = "rw"; };
			"$HOME/.cache/chromium" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/chromium" = { perm = "rw"; mkdir = true; };
			"/etc/hostname" = { perm = "ro"; };
			"/run/user/1000" = { perm = "ro"; };
			"/run/user/1000/bus" = { perm = "ro"; };
			"/run/user/1000/pipewire-0" = { perm = "ro"; };
			"/run/user/1000/pipewire-0-manager" = { perm = "ro"; };
			"/run/user/1000/pulse" = { perm = "ro"; };
			"/tmp" = { perm = "rw"; };
			"/usr/share/keyd" = { perm = "ro"; };
			"/usr/share/keyd/keyd.compose" = { perm = "ro"; };
		};
		network = true;
		mount_dev = true;
	};
	bin = launcher.mkLauncher {
		name = "chromium";
		target = "${pkgs.ungoogled-chromium}/bin/chromium";
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "chromium";
		inherit pkgs bin sandbox_restrictions;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
