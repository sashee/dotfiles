let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	nvim = (import ./nvim {
	});
	npm = (import ./npm {
	});
	res = pkgs.symlinkJoin {
		name = "nix-utils-custom";
		paths = [nvim npm];
	};
in
	res
