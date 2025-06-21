{}:
import ../wrapper.nix {
	name = "aws";
	get_landrun_requirements = {pkgs}: ''
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

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	get_bin = {pkgs}: "${pkgs.awscli2}/bin/aws";
}
