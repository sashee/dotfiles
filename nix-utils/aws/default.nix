{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"$HOME/.aws" = "rw";
		};
		network = true;
	};
	bin = launcher.mkLauncher {
		name = "aws";
		target = "${pkgs.awscli2}/bin/aws";
		keepEnv = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" "AWS_REGION" "LANG" "TERM"];
		setEnv = {
			SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
		};
	};
	before = ''
	'';

	sandbox_setup = ''

	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "aws";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
