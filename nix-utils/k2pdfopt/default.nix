{
	pkgs,
}:
let
	nixpkgs2 = fetchTarball {
		url = "https://github.com/NixOS/nixpkgs/archive/ac62194c3917d5f474c1a844b6fd6da2db95077d.tar.gz";
		sha256 = "0v6bd1xk8a2aal83karlvc853x44dg1n4nk08jg3dajqyy0s98np";
	};
	pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

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
		target = "${pkgs2.k2pdfopt}/bin/k2pdfopt";
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
