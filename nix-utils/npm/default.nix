{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	base_sandbox_restrictions = {
		fs = {
			"$HOME/.npm" = "rw";
			"$HOME/.npmrc" = "rw";
			"$HOME/.cache" = "rw";
		};
		network = true;
	};

	certEnv = {
		SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
		NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
	};

	node_tool_bin = launcher.mkLauncher {
		name = "node";
		target = "${pkgs.nodePackages_latest.nodejs}/bin/node";
		setEnv = certEnv;
	};

	npm_bin = node_tool_bin.override (_: {
		name = "npm";
		target = "${pkgs.nodePackages_latest.nodejs}/bin/npm";
	});

	node_bin = node_tool_bin;

	npx_bin = node_tool_bin.override (_: {
		name = "npx";
		target = "${pkgs.nodePackages_latest.nodejs}/bin/npx";
	});

	base_before = ''
	'';

	base_sandbox_setup = ''
	'';

	npm_scripts = (import ../_wrapper/default.nix {
		name = "npm";
		inherit pkgs;
		bin = npm_bin;
		sandbox_restrictions = base_sandbox_restrictions;
		before = base_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

	node_scripts = (import ../_wrapper/default.nix {
		name = "node";
		inherit pkgs;
		bin = node_bin;
		sandbox_restrictions = base_sandbox_restrictions;
		before = base_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

  	node_nonet_scripts = (import ../_wrapper/default.nix {
  		name = "node-nonet";
  		inherit pkgs;
	  		bin = node_bin;
  		sandbox_restrictions = {};  # unrestricted filesystem, no network
  		before = base_before;
  		sandbox_setup = base_sandbox_setup;
 		generate_unsafe = false;
 	}).scripts;

	npx_scripts = (import ../_wrapper/default.nix {
		name = "npx";
		inherit pkgs;
		bin = npx_bin;
		sandbox_restrictions = base_sandbox_restrictions;
		before = base_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

	npx_fullnet_scripts = (import ../_wrapper/default.nix {
		name = "npx-fullnet";
		inherit pkgs;
		bin = npx_bin;
		sandbox_restrictions = base_sandbox_restrictions // { network = true; };  # with network
		before = base_before;
		sandbox_setup = base_sandbox_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = npm_scripts ++ node_scripts ++ node_nonet_scripts ++ npx_scripts ++ npx_fullnet_scripts;
	sandbox_restrictions = base_sandbox_restrictions;
}
