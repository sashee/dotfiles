{
	pkgs,
}:
let
	bin = "${pkgs.awslogs}/bin/awslogs";
	sandbox_restrictions = {
		fs = {
			"~/.aws" = "ro";
		};
		env = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" "AWS_REGION" "LANG" "TERM"];
		network = true;
	};
	before = ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "awslogs";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}

