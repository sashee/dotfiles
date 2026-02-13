{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	keepEnv = ["TERM"];
	sandbox_restrictions = {
		network = false;
	};
	bin = launcher.mkLauncher {
		name = "k2pdfopt";
		target = "${pkgs.k2pdfopt}/bin/k2pdfopt";
		inherit keepEnv;
	};
	before = ''

	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "k2pdfopt";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
