{
	pkgs,
}:
let
	nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
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
