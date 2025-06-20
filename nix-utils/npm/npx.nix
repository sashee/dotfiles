{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	landrun_requirements = ''
			--rox /usr,/dev,/nix \
			--rox ~/.npm \
			--rwx /dev/null \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env LANG \
			--env AWS_ACCESS_KEY_ID \
			--env AWS_SECRET_ACCESS_KEY \
			--env AWS_SESSION_TOKEN \
			--env AWS_REGION \
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
${pkgs.nodePackages_latest.nodejs}/bin/npx "$@"
	'';

	npx = pkgs.writeShellScriptBin "npx" (makeWrapper {landRun = runInLandRun;});
	npx_default = pkgs.writeShellScriptBin "npx-default" (makeWrapper {landRun = "";});
in
	{
		scripts = [
			npx
			npx_default
		];
		inherit landrun_requirements landrun_setup;
	}

