{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	keepEnv = ["TERM" "HOME" "PATH"];
	sandbox_restrictions = {
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "lazysql";
		target = "${pkgs.lazysql}/bin/lazysql";
		inherit keepEnv;
		setEnv = {
			PATH = pkgs.lib.makeBinPath [
				pkgs.ncurses
			];
		};
	};
	before = ''
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "lazysql";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
