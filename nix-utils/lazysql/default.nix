{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "lazysql";
		target = "${pkgs.lazysql}/bin/lazysql";
		keepEnv = ["TERM" "HOME" "PATH"];
		setEnv = {
			PATH = pkgs.lib.makeBinPath [
				pkgs.ncurses
			];
		};
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "lazysql";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
