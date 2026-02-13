{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "fx";
		target = "${pkgs.fx}/bin/fx";
		keepEnv = ["TERM" "HOME"];
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "fx";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
