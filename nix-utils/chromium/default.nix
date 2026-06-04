{
	pkgs,
	nixgl,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	nixglWrapper = nixgl.auto.nixGLDefault;
	nixglChromium = pkgs.writeShellScript "chromium-with-nixgl" ''
		exec ${nixglWrapper}/bin/nixGL ${pkgs.ungoogled-chromium}/bin/chromium "$@"
	'';
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
			"$XDG_RUNTIME_DIR" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/bus" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pipewire-0" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pipewire-0-manager" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pulse" = { perm = "ro"; };
			"/tmp" = { perm = "rw"; };
			"/usr/share/keyd" = { perm = "ro"; };
			"/usr/share/keyd/keyd.compose" = { perm = "ro"; };
		};
		network = true;
		dev = true;
		share_user = true;
		share_ipc = true;
	};
	bin = launcher.mkLauncher {
		name = "chromium";
		target = "${nixglChromium}";
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
