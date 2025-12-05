{
	pkgs,
}:
let
	bin = "${pkgs.flameshot}/bin/flameshot";
	sandbox_restrictions = {
		network = {};
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "flameshot";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
