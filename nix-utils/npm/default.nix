{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	base_sandbox_restrictions = {
		fs = {
			"$HOME/.npm" = { perm = "rw"; };
			# Scoped to the cache subdirs node tooling actually uses, instead of
			# all of ~/.cache, so untrusted package scripts can't poison other
			# tools' caches (which non-sandboxed host processes later trust).
			"$HOME/.cache/pnpm" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/node" = { perm = "rw"; mkdir = true; };
			"$HOME/.cache/node-gyp" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/share/pnpm" = { perm = "rw"; };
		};
		network = true;
	};

	certEnv = {
		SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
		NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
	};

	node_tool_bin = launcher.mkLauncher {
		name = "node";
		target = "${pkgs.nodejs}/bin/node";
		setEnv = certEnv;
	};

	npm_bin = node_tool_bin.override (_: {
		name = "npm";
		target = "${pkgs.nodejs}/bin/npm";
	});

	node_bin = node_tool_bin;

	npx_bin = node_tool_bin.override (_: {
		name = "npx";
		target = "${pkgs.nodejs}/bin/npx";
	});

	npm_scripts = (import ../_wrapper/default.nix {
		name = "npm";
		inherit pkgs;
		bin = npm_bin;
		sandbox_restrictions = base_sandbox_restrictions;
	}).scripts;

	node_scripts = (import ../_wrapper/default.nix {
		name = "node";
		inherit pkgs;
		bin = node_bin;
		sandbox_restrictions = base_sandbox_restrictions;
	}).scripts;

  	node_nonet_scripts = (import ../_wrapper/default.nix {
  		name = "node-nonet";
  		inherit pkgs;
	  		bin = node_bin;
  		sandbox_restrictions = {};  # unrestricted filesystem, no network
  		generate_unsafe = false;
  	}).scripts;

	npx_scripts = (import ../_wrapper/default.nix {
		name = "npx";
		inherit pkgs;
		bin = npx_bin;
		sandbox_restrictions = base_sandbox_restrictions;
	}).scripts;

	npx_fullnet_scripts = (import ../_wrapper/default.nix {
		name = "npx-fullnet";
		inherit pkgs;
		bin = npx_bin;
		sandbox_restrictions = base_sandbox_restrictions // { network = true; };  # with network
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = npm_scripts ++ node_scripts ++ node_nonet_scripts ++ npx_scripts ++ npx_fullnet_scripts;
	sandbox_restrictions = base_sandbox_restrictions;
}
