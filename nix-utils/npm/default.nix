{
	pkgs,
}:
let
	consts = import ../consts.nix;

	base_sandbox_restrictions = {
		fs = {
			"~/.npm" = "rw";
			"~/.npmrc" = "rw";
			"~/.cache" = "rw";
		};
		network = {};
	};

	base_before = ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
export NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	base_sandbox_setup = ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
export NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	npx_before = base_before + ''
export ${consts.SKIP_SANDBOX_ENV_VAR_NAME}="true"
	'';

	npm_scripts = (import ../wrapper.nix {
		name = "npm";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/npm";
		sandbox_restrictions = base_sandbox_restrictions;
		before = base_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

	node_scripts = (import ../wrapper.nix {
		name = "node";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/node";
		sandbox_restrictions = base_sandbox_restrictions;
		before = base_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

 	node_nonet_scripts = (import ../wrapper.nix {
 		name = "node-nonet";
 		inherit pkgs;
 		bin = "${pkgs.nodePackages_latest.nodejs}/bin/node";
 		sandbox_restrictions = {};  # unrestricted filesystem, no network
 		before = base_before;
 		sandbox_setup = base_sandbox_setup;
 		generate_unsafe = false;
 	}).scripts;

	npx_scripts = (import ../wrapper.nix {
		name = "npx";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		sandbox_restrictions = base_sandbox_restrictions;
		before = npx_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

	npx_fullnet_scripts = (import ../wrapper.nix {
		name = "npx-fullnet";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		sandbox_restrictions = base_sandbox_restrictions // { network = {}; };  # with network
		before = npx_before;
		sandbox_setup = base_sandbox_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = npm_scripts ++ node_scripts ++ node_nonet_scripts ++ npx_scripts ++ npx_fullnet_scripts;
	sandbox_restrictions = base_sandbox_restrictions;
}
