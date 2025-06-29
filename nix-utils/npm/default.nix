{}:
let
	consts = import ../consts.nix;

	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix \
			--rwx ~/.npm \
			--rwx ~/.npmrc \
			--rwx /dev/null \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--rox /etc/fonts \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env LANG \
			--env NPM_TOKEN_WEARIN \
			--env AWS_ACCESS_KEY_ID \
			--env AWS_SECRET_ACCESS_KEY \
			--env AWS_SESSION_TOKEN \
			--env AWS_REGION \
			\
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--env XDG_CACHE_DIR \
			\
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
		name = "node-nonet";
		inherit get_landrun_setup get_before;
		get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/node";
		get_landrun_requirements = {pkgs}: (get_landrun_requirements {inherit pkgs;} + ''
			--unrestricted-filesystem \
		'');
		generate_unsafe = false;
	})
	(wrapper {
		name = "npx";
		inherit get_landrun_requirements get_landrun_setup;
		get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		get_before = {pkgs} : (get_before {inherit pkgs;} + ''
export ${consts.SKIP_SANDBOX_ENV_VAR_NAME}="true"
		'');
	})
	(wrapper {
		name = "npx-fullnet";
		inherit get_landrun_setup;
		get_bin = {pkgs}: "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		get_before = {pkgs} : (get_before {inherit pkgs;} + ''
export ${consts.SKIP_SANDBOX_ENV_VAR_NAME}="true"
		'');
		get_landrun_requirements = {pkgs}: (get_landrun_requirements {inherit pkgs;} + ''
			--unrestricted-network \
		'');
		generate_unsafe = false;
	})
]
