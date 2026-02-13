{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		network = true;
	};
	bin = launcher.mkLauncher {
		name = "wormhole";
		target = "${pkgs.magic-wormhole}/bin/wormhole";
		keepEnv = ["TERM"];
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "wormhole";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
