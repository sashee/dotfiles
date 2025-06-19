{
	pkgs
}:
let
	runInLandRun =''
		${pkgs.landrun}/bin/landrun \
			--rox /usr,/dev,/nix \
			--rwx ~/.aws \
			--rwx ''$(${pkgs.nodePackages_latest.nodejs}/bin/node -e 'console.log([path.relative(path.join(process.env.HOME, "workspace"), process.cwd()).split(path.sep)].map((rel) => rel[0].startsWith(".") ? process.cwd() : path.join(process.env.HOME, "workspace", rel[0]))[0])') \
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

	makeWrapper = {landRun}: ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

${landRun} \
${pkgs.awscli2}/bin/aws "$@"
	'';

	aws = pkgs.writeShellScriptBin "aws" (makeWrapper {landRun = runInLandRun;});
	aws_default = pkgs.writeShellScriptBin "aws-default" (makeWrapper {landRun = "";});
in
	[
		aws
		aws_default
	]

