{
	pkgs,
}:
let
	packageName = "nvim-custom";
	launcher = import ../launcher.nix { inherit pkgs; };

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

	nvimPath = pkgs.lib.makeBinPath [
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
	];

	nvim_bin = launcher.mkLauncher {
		name = "nvim";
		target = "${pkgs.neovim-unwrapped}/bin/nvim";
		keepEnv = [ "HOME" "PATH" "NVIM_RPLUGIN_MANIFEST" "TMPDIR" "SSL_CERT_FILE" "TERM" "LANG" ];
		setEnv = {
			PATH = nvimPath;
			SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
			NVIM_RPLUGIN_MANIFEST = "${./rplugin.vim}";
		};
		extraArgs = [
			"-u"
			"${./init.lua}"
			"--cmd"
			"set packpath^=${packpath} | set runtimepath^=${packpath}"
		];
	};

	nvim_net_bin = nvim_bin.override (old: {
		name = "nvim-net";
		keepEnv = old.keepEnv ++ [ "AWS_REGION" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" ];
	});

	base_sandbox_restrictions = {
		fs = {
			"$HOME/.local/state/nvim" = "rw";
			"$HOME/.local/share/nvim" = "rw";
			"$HOME/.cache" = "rw";
			"$HOME/.gitconfig" = "ro";
		};
		files = {
			"/home/sashee/eslint.config.js" = "${eslintConfig}";
		};
		network = false;
	};

	base_sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.local/state/nvim
		${pkgs.coreutils}/bin/mkdir -p $HOME/.cache
	'';

	nvim_scripts = (import ../_wrapper/default.nix {
		name = "nvim";
		inherit pkgs;
		bin = nvim_bin;
		sandbox_restrictions = base_sandbox_restrictions;
		sandbox_setup = base_sandbox_setup;
	}).scripts;

	nvim_net_scripts = (import ../_wrapper/default.nix {
		name = "nvim-net";
		inherit pkgs;
		bin = nvim_net_bin;
		sandbox_restrictions = base_sandbox_restrictions // {
			network = true;
		};
		sandbox_setup = base_sandbox_setup;
		generate_unsafe = false;
	}).scripts;
in
{
	scripts = nvim_scripts ++ nvim_net_scripts;
	sandbox_restrictions = base_sandbox_restrictions;
}
