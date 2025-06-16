let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

	runInLandRun =''
		${pkgs.landrun}/bin/landrun \
			--rox /usr,/dev,/nix \
			--rwx ~/.npm \
			--rwx ''$(${pkgs.nodePackages_latest.nodejs}/bin/node -e 'console.log([path.relative(path.join(process.env.HOME, "workspace"), process.cwd()).split(path.sep)].map((rel) => rel[0].startsWith(".") ? process.cwd() : path.join(process.env.HOME, "workspace", rel[0]))[0])') \
			--rwx /dev/null \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env LANG \
			--connect-tcp 443 \
	'';

	makeWrapper = {landRun}: ''
${landRun} \
${pkgs.nodePackages_latest.nodejs}/bin/npm "$@"
	'';

	npm = pkgs.writeShellScriptBin "npm" (makeWrapper {landRun = runInLandRun;});
	npm_default = pkgs.writeShellScriptBin "npm-default" (makeWrapper {landRun = "";});

	res = pkgs.symlinkJoin {
		name = "npm-custom";
		paths = [npm npm_default];
	};
in
	res

