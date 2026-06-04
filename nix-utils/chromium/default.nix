{
	pkgs,
	nixgl,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	chromiumTarget = "${pkgs.ungoogled-chromium}/bin/chromium";
	wrappedChromium = pkgs.writeShellScript "chromium-with-nixgl" ''
		exec ${nixgl.auto.nixGLDefault}/bin/nixGL ${chromiumTarget} "$@"
	'';
	target = if nixgl == null then chromiumTarget else "${wrappedChromium}";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.XCompose" = { perm = "ro"; };
			"$HOME/.config/chromium" = { perm = "rw"; mkdir = true; };
			"$HOME/Downloads" = { perm = "rw"; };
			"$HOME/.cache/chromium" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/chromium" = { perm = "rw"; mkdir = true; };
			"$XDG_RUNTIME_DIR" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/bus" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pipewire-0" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pipewire-0-manager" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pulse" = { perm = "ro"; };
			"/tmp" = { perm = "rw"; };
		};
		network = true;
		dev = true;
		share_user = true;
		share_ipc = true;
	};
	bin = launcher.mkLauncher {
		name = "chromium";
		inherit target;
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
