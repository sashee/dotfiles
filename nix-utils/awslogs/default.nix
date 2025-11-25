{
	pkgs,
}:
let
	bin = "${pkgs.awslogs}/bin/awslogs";
	landrun_restrictions = {
		fs = {
			"/usr" = "rox";
			"/dev" = "rox";
			"/nix" = "rox";
			"/run/systemd/resolve" = "rox";
			"~/.aws" = "rox";
			"/dev/null" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
			"/etc/ssl" = "ro";
		};
		env = ["HOME" "PATH" "TMPDIR" "SSL_CERT_FILE" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" "AWS_REGION" "LANG" "TERM"];
		network = {
			tcp = {
				connect = [443];
			};
		};
	};
	before = ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	landrun_setup = ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "awslogs";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}

