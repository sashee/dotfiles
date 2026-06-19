{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	bins = (map (bin: pkgs.libreoffice + "/bin/" + bin) (builtins.attrNames (builtins.readDir (pkgs.libreoffice + "/bin"))));

	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = { perm = "ro"; };
			"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" = { perm = "ro"; };
			"$HOME/.Xauthority" = { perm = "ro"; };
			"$HOME/.config/libreoffice" = { perm = "rw"; mkdir = true; };
			"$XDG_RUNTIME_DIR/libreoffice-dbus" = { perm = "rw"; mkdir = true;};
			# Opt back into CUPS (blocked in consts.nix for everyone else) so printing
			# works. ro is enough — connect() to the socket needs no fs write.
			"/run/cups" = { perm = "ro"; };
			"$HOME" = {perm = "rw";};
		};
		network = false;
	};

	scripts = builtins.concatLists (map (bin: (import ../_wrapper/default.nix {
		name = builtins.baseNameOf bin;
		inherit pkgs sandbox_restrictions;
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
