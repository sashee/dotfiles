{
	pkgs,
}:
let
	packageName = "nvim-custom";

	eslintConfig = pkgs.writeText "eslint.config.js" ''
export default [
	{
		"rules": {
		"indent": [
		    "error",
		    "tab"
		],
		"linebreak-style": [
		    "error",
		    "unix"
		],
		"quotes": [
		    "error",
		    "double"
		],
		"semi": [
		    "error",
		    "always"
		],
					"no-console": "off"
	    }
	},
];
'';

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
		pkgs.vimPlugins.neotest
		pkgs.vimPlugins.neotest-jest
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
		pkgs.vimPlugins.blame-nvim
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

	base_sandbox_restrictions = {
		fs = {
			"~/.local/state/nvim" = "rw";
			"~/.local/share/nvim" = "rw";
			"~/.cache" = "rw";
			"~/.gitconfig" = "ro";
		};
		files = {
			"/home/sashee/eslint.config.js" = "${eslintConfig}";
		};
		env = ["HOME" "PATH" "NVIM_RPLUGIN_MANIFEST" "TMPDIR" "SSL_CERT_FILE" "TERM" "LANG"];
		network = true;
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
		pkgs.dockerfile-language-server
		pkgs.marksman
		pkgs.terraform-ls
		pkgs.nixd
	]
}"
export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

export NVIM_RPLUGIN_MANIFEST=${./rplugin.vim}
	'';

	base_sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.local/state/nvim
		${pkgs.coreutils}/bin/mkdir -p ~/.cache
	'';

	nvim_scripts = (import ../wrapper.nix {
		name = "nvim";
		inherit pkgs bin;
		sandbox_restrictions = base_sandbox_restrictions;
		before = base_before;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

	nvim_net_scripts = (import ../wrapper.nix {
		name = "nvim-net";
		inherit pkgs bin;
		sandbox_restrictions = base_sandbox_restrictions // {
			env = base_sandbox_restrictions.env ++ ["AWS_REGION" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN"];
			network = true;
		};
		before = base_before;
		sandbox_setup = base_sandbox_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = nvim_scripts ++ nvim_net_scripts;
	sandbox_restrictions = base_sandbox_restrictions;
}
