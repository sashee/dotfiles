{
	pkgs,
}:
let
	bin = "${pkgs.k2pdfopt}/bin/k2pdfopt";
	sandbox_restrictions = {
		env = ["TERM"];
		network = false;
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "k2pdfopt";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
