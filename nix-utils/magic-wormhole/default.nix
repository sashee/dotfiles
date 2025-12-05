{
	pkgs,
}:
let
	bin = "${pkgs.magic-wormhole}/bin/wormhole";
	sandbox_restrictions = {
		env = ["TERM"];
		network = true;
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "wormhole";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}