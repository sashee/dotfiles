{
	pkgs,
}:
let
	nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
	pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

	packageName = "nvim-custom";

	startPlugins = [
		pkgs.vimPlugins.nvim-surround
		pkgs.vimPlugins.gitsigns-nvim
		pkgs.vimPlugins.nvim-solarized-lua
		pkgs.vimPlugins.nui-nvim
		pkgs.vimPlugins.neo-tree-nvim
		pkgs.vimPlugins.hop-nvim
		pkgs.vimPlugins.nvim-autopairs
		pkgs.vimPlugins.rainbow-delimiters-nvim
		pkgs.vimPlugins.nvim-nio
		pkgs2.vimPlugins.neotest
		pkgs2.vimPlugins.neotest-jest
		pkgs.vimPlugins.telescope-nvim
		pkgs.vimPlugins.nvim-treesitter
		pkgs.vimPlugins.nvim-treesitter.withAllGrammars
		pkgs.vimPlugins.nvim-lspconfig
		pkgs.vimPlugins.cmp-nvim-lsp
		pkgs.vimPlugins.cmp-buffer
		pkgs.vimPlugins.cmp-path
		pkgs.vimPlugins.cmp-cmdline
		pkgs.vimPlugins.nvim-cmp
		pkgs.vimPlugins.lsp_signature-nvim
		pkgs.vimPlugins.tiny-inline-diagnostic-nvim
		pkgs.vimPlugins.nvim-web-devicons
	];

	foldPlugins = builtins.foldl' (
		acc: next:
			acc
			++ [
				next
			]
			++ (foldPlugins (next.dependencies or []))
	) [];

	startPluginsWithDeps = pkgs.lib.unique (foldPlugins startPlugins);

	packpath = pkgs.runCommandLocal "packpath" {} ''
		${pkgs.coreutils}/bin/mkdir -p $out/pack/${packageName}/{start,opt}

		${
			pkgs.lib.concatMapStringsSep
			"\n"
			(plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${pkgs.lib.getName plugin}")
			startPluginsWithDeps
		}
	'';

	bin = ''
		${pkgs.neovim-unwrapped}/bin/nvim \
		-u ${./init.lua} \
		--cmd 'set packpath^=${packpath} | set runtimepath^=${packpath}' \
	'';

	base_landrun_restrictions = {
		fs = {
			"/usr" = "rox";
			"/dev" = "rox";
			"/nix" = "rox";
			"/proc" = "rox";
			"/dev/ptmx" = "rwx";
			"/dev/pts" = "rwx";
			"/dev/null" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
			"~/.local/state/nvim" = "rwx";
			"~/.cache" = "rwx";
			"~/eslint.config.js" = "ro";
			"~/.gitconfig" = "ro";
		};
		env = ["HOME" "PATH" "NVIM_RPLUGIN_MANIFEST" "TMPDIR" "SSL_CERT_FILE" "TERM" "LANG"];
		network = {};
	};

	base_before = ''
export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.lua-language-server
		pkgs.typescript-language-server
		pkgs.bash
		pkgs.nodePackages.nodejs
		pkgs.git
		pkgs.ripgrep
		pkgs.tmux
		pkgs.man
		pkgs.coreutils
		pkgs.gzip
		pkgs.unzip
		pkgs.gnutar
		pkgs.unixtools.ping
		pkgs.curl
		pkgs.netcat
		pkgs.eslint
		pkgs.vscode-langservers-extracted
		pkgs.rust-analyzer
		pkgs.cargo
		pkgs.yaml-language-server
		pkgs.bash-language-server
		pkgs.dockerfile-language-server-nodejs
		pkgs.marksman
		pkgs.terraform-ls
		pkgs.nixd
	]
}"
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

export NVIM_RPLUGIN_MANIFEST=${./rplugin.vim}
	'';

	base_landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.local/state/nvim
		${pkgs.coreutils}/bin/mkdir -p ~/.cache
	'';

	nvim_scripts = (import ../wrapper.nix {
		name = "nvim";
		inherit pkgs bin;
		landrun_restrictions = base_landrun_restrictions;
		before = base_before;
		landrun_setup = base_landrun_setup;
	}).scripts;

	nvim_net_scripts = (import ../wrapper.nix {
		name = "nvim-net";
		inherit pkgs bin;
		landrun_restrictions = base_landrun_restrictions // {
			fs = base_landrun_restrictions.fs // {
				"/run/systemd/resolve" = "rox";
			};
			env = base_landrun_restrictions.env ++ ["AWS_REGION" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN"];
			network = {
				tcp = {
					connect = [443 8883];
				};
			};
		};
		before = base_before;
		landrun_setup = base_landrun_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = nvim_scripts ++ nvim_net_scripts;
	landrun_restrictions = base_landrun_restrictions;
}
