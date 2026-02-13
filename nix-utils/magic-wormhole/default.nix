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
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "wormhole";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
