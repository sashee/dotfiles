{
	pkgs,
}:
let
	bin = "${pkgs.ungoogled-chromium}/bin/chromium";
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"$HOME/.Xauthority" = "ro";
			"$HOME/.XCompose" = "ro";
			"$HOME/.config/chromium" = "rw";
			"$HOME/Downloads" = "rw";
			"$HOME/.cache/chromium" = "rw";
			"$HOME/.local/share/chromium" = "rw";
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
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/chromium
		${pkgs.coreutils}/bin/mkdir -p $HOME/.cache/chromium
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/share/chromium
	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "chromium";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
		restrict_to_current_folder = false;
	}).scripts;
	inherit sandbox_restrictions;
}
