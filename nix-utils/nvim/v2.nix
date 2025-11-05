{
	pkgs,
}:
let
	landrun_requirements = ''
			--rox /usr,/dev,/nix,/proc \
			--rwx /dev/ptmx \
			--rwx /dev/pts \
			--rwx /dev/null \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--rwx ~/.local/state/nvim \
			--rwx ~/.cache \
			--ro ~/eslint.config.js \
			--ro ~/.gitconfig \
			--env HOME \
			--env PATH \
			--env NVIM_RPLUGIN_MANIFEST \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env TERM \
			--env LANG \
	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.local/state/nvim
		${pkgs.coreutils}/bin/mkdir -p ~/.cache
	'';

	before = ''
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

	bin = let
		packageName = "nvim-custom";

		nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
		pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

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
	in ''
		${pkgs.neovim-unwrapped}/bin/nvim \
		-u ${./init.lua} \
		--cmd 'set packpath^=${packpath} | set runtimepath^=${packpath}' \
	'';

	wrapper = import ../wrapper.nix;
in
[
	(wrapper {
	 name = "nvim";
	 inherit get_landrun_requirements get_landrun_setup get_before get_bin;
	})
	(wrapper {
		name = "nvim-net";
		inherit get_landrun_setup get_before get_bin;
		get_landrun_requirements = {pkgs}: (get_landrun_requirements {inherit pkgs;} + ''
			--rox /run/systemd/resolve \
			--connect-tcp 443 \
			--connect-tcp 8883 \
			--env AWS_REGION \
			--env AWS_ACCESS_KEY_ID \
			--env AWS_SECRET_ACCESS_KEY \
			--env AWS_SESSION_TOKEN \
		'');
		generate_unsafe = false;
	})
]
