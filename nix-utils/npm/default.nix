{}:
let
	get_landrun_requirements = {pkgs}: ''
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

	get_landrun_setup = {pkgs}: ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	get_before = {pkgs}: ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	wrapper = import ../wrapper.nix;
in
[
	(wrapper {
	 name = "npm";
	 inherit get_landrun_requirements get_landrun_setup get_before;
	 get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/npm";
	})
	(wrapper {
		name = "node";
		inherit get_landrun_requirements get_landrun_setup get_before;
		get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/node";
	})
	(wrapper {
		name = "npx";
		inherit get_landrun_requirements get_landrun_setup;
		get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		get_before = {pkgs} : (get_before {inherit pkgs;} + ''
export SKIP_SANDBOX="true"
		'');
	})
	(wrapper {
		name = "npx-fullnet";
		inherit get_landrun_setup;
		get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		get_before = {pkgs} : (get_before {inherit pkgs;} + ''
export SKIP_SANDBOX="true"
		'');
		get_landrun_requirements = {pkgs}: (get_landrun_requirements {inherit pkgs;} + ''
			--unrestricted-network \
		'');
		generate_unsafe = false;
	})
]
