{
	pkgs,
}:
let
	bins = (map (bin: pkgs.libreoffice + "/bin/" + bin) (builtins.attrNames (builtins.readDir (pkgs.libreoffice + "/bin"))));

	sandbox_restrictions = {
		fs = {
			"/tmp/.X11-unix" = "ro";
			"~/.Xauthority" = "ro";
			"~/.config/libreoffice" = "rw";
		};
		env = ["DISPLAY" "XAUTHORITY" "HOME" "PATH" "TMPDIR" "LANG" "TERM" "XDG_CONFIG_HOME" "XDG_DATA_DIRS" "XDG_RUNTIME_DIR"];
		network = false;
	};

	before = ''

	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/libreoffice
	'';

	scripts = builtins.concatLists (map (bin: (import ../wrapper.nix {
		name = builtins.baseNameOf bin;
		inherit pkgs sandbox_restrictions before sandbox_setup;
		bin = bin;
		restrict_to_current_folder = false;
	}).scripts) bins);
in
{
	inherit scripts sandbox_restrictions;
}
