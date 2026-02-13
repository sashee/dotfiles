{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.local/share/vlc" = { perm = "rw"; mkdir = true; };
			"$HOME/.config/vlc" = { perm = "rw"; mkdir = true; };
			"/run/user/1000/pipewire-0" = { perm = "ro"; };
			"/run/user/1000/pulse" = { perm = "ro"; };
		};
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "vlc";
		target = "${pkgs.vlc}/bin/vlc";
		keepEnv = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		extraArgs = [ "--no-qt-privacy-ask" ];
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "vlc";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
