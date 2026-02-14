{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		network = false;
		seccomp = {
			block = {
				AF_UNIX = true;
			};
		};
	};
	bin = launcher.mkLauncher {
		name = "k2pdfopt";
		target = "${pkgs.k2pdfopt}/bin/k2pdfopt";
		keepEnv = ["TERM"];
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "k2pdfopt";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
