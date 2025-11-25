{
	pkgs,
}:
let
	consts = import ../consts.nix;

	base_landrun_restrictions = {
		fs = {
			"/usr" = "rox";
			"/dev" = "rox";
			"/nix" = "rox";
			"/etc" = "rox";
			"/run/systemd/resolve" = "rox";
			"~/.npm" = "rwx";
			"~/.npmrc" = "rwx";
			"~/.cache" = "rwx";
			"/dev/null" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
			"/etc/fonts" = "rox";
			"/etc/ssl" = "ro";
		};
		network = {
			tcp = {
				connect = [443 8883];
				bind = [8080];
			};
		};
	};

	base_before = ''
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
export NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
	'';

	base_landrun_setup = ''
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
		landrun_restrictions = base_landrun_restrictions;
		before = base_before;
		landrun_setup = base_landrun_setup;
	}).scripts;

	node_scripts = (import ../wrapper.nix {
		name = "node";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/node";
		landrun_restrictions = base_landrun_restrictions;
		before = base_before;
		landrun_setup = base_landrun_setup;
	}).scripts;

 	node_nonet_scripts = (import ../wrapper.nix {
 		name = "node-nonet";
 		inherit pkgs;
 		bin = "${pkgs.nodePackages_latest.nodejs}/bin/node";
 		landrun_restrictions = { network = {}; };  # unrestricted filesystem, no network
 		before = base_before;
 		landrun_setup = base_landrun_setup;
 		generate_unsafe = false;
 	}).scripts;

	npx_scripts = (import ../wrapper.nix {
		name = "npx";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		landrun_restrictions = base_landrun_restrictions;
		before = npx_before;
		landrun_setup = base_landrun_setup;
	}).scripts;

	npx_fullnet_scripts = (import ../wrapper.nix {
		name = "npx-fullnet";
		inherit pkgs;
		bin = "${pkgs.nodePackages_latest.nodejs}/bin/npx";
		landrun_restrictions = base_landrun_restrictions // { network = {}; };  # unrestricted network
		before = npx_before;
		landrun_setup = base_landrun_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = npm_scripts ++ node_scripts ++ node_nonet_scripts ++ npx_scripts ++ npx_fullnet_scripts;
	landrun_restrictions = base_landrun_restrictions;
}
