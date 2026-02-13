{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	bins = (map (bin: pkgs.libreoffice + "/bin/" + bin) (builtins.attrNames (builtins.readDir (pkgs.libreoffice + "/bin"))));

	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"$HOME/.Xauthority" = "ro";
			"$HOME/.config/libreoffice" = "rw";
		};
		network = false;
	};

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/libreoffice
	'';

	scripts = builtins.concatLists (map (bin: (import ../_wrapper/default.nix {
		name = builtins.baseNameOf bin;
		inherit pkgs sandbox_restrictions sandbox_setup;
		bin = launcher.mkLauncher {
			name = builtins.baseNameOf bin;
			target = bin;
			keepEnv = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "LANG" "TERM" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		};
		restrict_to_current_folder = false;
	}).scripts) bins);
in
{
	inherit scripts sandbox_restrictions;
}
