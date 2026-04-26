{
	pkgs,
	nixgl,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	nixglWrapper = nixgl.nixVulkanIntel;
	nixglVkQuake = pkgs.writeShellScript "vkquake-with-nixgl" ''
		exec ${nixglWrapper}/bin/nixVulkanIntel ${pkgs.vkquake}/bin/vkquake "$@"
	'';
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.vkquake" = { perm = "rw"; };
			"$HOME/quake" = { perm = "rw"; };
			"/run/user/1000/pipewire-0" = { perm = "ro"; };
			"/run/user/1000/pulse" = { perm = "ro"; };
			"/tmp" = { perm = "rw"; };
		};
		network = false;
		dev = true;
	};
	bin = launcher.mkLauncher {
		name = "chromium";
		target = "${nixglVkQuake}";
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

