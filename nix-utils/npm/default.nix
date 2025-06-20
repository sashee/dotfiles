{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	landrun_requirements = ''
			--rox /usr,/dev,/nix \
			--rwx ~/.npm \
			--rwx /dev/null \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env LANG \
			--env NPM_TOKEN_WEARIN \
			--connect-tcp 443 \
	'';

	landrun_setup = ''
	'';

	runInLandRun =''
	${landrun_setup}

		RESTRICT_TO=$(${utils.findGitRoot}/bin/findGitRoot)

		echo "Restricting to folder: $RESTRICT_TO"

		${pkgs.landrun}/bin/landrun \
			--rwx ''$RESTRICT_TO \
			${landrun_requirements} \
	'';

	makeWrapper = {landRun}: ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

${landRun} \
${pkgs.nodePackages_latest.nodejs}/bin/npm "$@"
	'';

	npm = pkgs.writeShellScriptBin "npm" (makeWrapper {landRun = runInLandRun;});
	npm_default = pkgs.writeShellScriptBin "npm-default" (makeWrapper {landRun = "";});
in
	{
		scripts = [
			npm
			npm_default
		];
		inherit landrun_requirements landrun_setup;
	}

