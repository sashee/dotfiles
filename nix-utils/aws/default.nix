{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	landrun_requirements = ''
			--rox /usr,/dev,/nix \
			--rwx ~/.aws \
			--rwx /dev/null \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env AWS_ACCESS_KEY_ID \
			--env AWS_SECRET_ACCESS_KEY \
			--env AWS_SESSION_TOKEN \
			--env AWS_REGION \
			--env LANG \
			--env TERM \
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
${pkgs.awscli2}/bin/aws "$@"
	'';

	aws = pkgs.writeShellScriptBin "aws" (makeWrapper {landRun = runInLandRun;});
	aws_default = pkgs.writeShellScriptBin "aws-default" (makeWrapper {landRun = "";});
in
	{
		scripts = [
			aws
			aws_default
		];
		inherit landrun_requirements landrun_setup;
	}

