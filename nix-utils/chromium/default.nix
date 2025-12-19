{
	pkgs,
}:
let
	bin = "${pkgs.ungoogled-chromium}/bin/chromium";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"~/.Xauthority" = "ro";
			"~/.XCompose" = "ro";
			"~/.config/chromium" = "rw";
			"~/Downloads" = "rw";
			"~/.cache/chromium" = "rw";
			"~/.local/share/chromium" = "rw";
			"/etc/hostname" = "ro";
			"/run/user/1000" = "ro";
			"/run/user/1000/bus" = "ro";
			"/run/user/1000/pipewire-0" = "ro";
			"/run/user/1000/pipewire-0-manager" = "ro";
			"/run/user/1000/pulse" = "ro";
			"/tmp" = "rw";
			"/usr/share/keyd" = "ro";
			"/usr/share/keyd/keyd.compose" = "ro";
		};
		network = true;
		mount_dev = true;
	};
	before = "";

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/chromium
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/chromium
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/chromium
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "chromium";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
