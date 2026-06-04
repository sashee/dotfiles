{
	pkgs,
	nixgl,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	vkquakeTarget = "${pkgs.vkquake}/bin/vkquake";
	wrappedVkquake = pkgs.writeShellScript "vkquake-with-nixgl" ''
		exec ${nixgl.nixVulkanIntel}/bin/nixVulkanIntel ${vkquakeTarget} "$@"
	'';
	target = if nixgl == null then vkquakeTarget else "${wrappedVkquake}";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.vkquake" = { perm = "rw"; };
			"$HOME/quake" = { perm = "rw"; };
			"$XDG_RUNTIME_DIR/pipewire-0" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/pulse" = { perm = "ro"; };
			"/tmp" = { perm = "rw"; };
		};
		network = false;
		dev = true;
	};
	bin = launcher.mkLauncher {
		name = "vkquake";
		inherit target;
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "vkquake";
		inherit pkgs bin sandbox_restrictions;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
