{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"$HOME/.Xauthority" = "ro";
			"$HOME/.local/share/vlc" = "rw";
			"$HOME/.config/vlc" = "rw";
			"/run/user/1000/pipewire-0" = "ro";
			"/run/user/1000/pulse" = "ro";
		};
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "vlc";
		target = "${pkgs.vlc}/bin/vlc";
		keepEnv = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		extraArgs = [ "--no-qt-privacy-ask" ];
	};
	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/share/vlc
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/vlc
	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "vlc";
		inherit pkgs bin sandbox_restrictions sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
