{
	pkgs,
}:
let
	bin = "${pkgs.fx}/bin/fx";
	sandbox_restrictions = {
		env = ["TERM" "HOME"];
		network = {};
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "fx";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
