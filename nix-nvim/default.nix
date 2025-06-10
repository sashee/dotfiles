let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };

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
    mkdir -p $out/pack/${packageName}/{start,opt}

    ${
      pkgs.lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${pkgs.lib.getName plugin}")
      startPluginsWithDeps
    }
  '';

	runInLandRun =''
		${pkgs.landrun}/bin/landrun \
			--rox /usr,/dev,/nix \
			--rwx . \
			--rwx /dev/ptmx \
			--rwx /dev/pts \
			--rwx /dev/null \
			--rwx "''${TMPDIR:-/tmp}" \
			--rwx ~/.local/state/nvim \
			--rwx ~/.cache \
			--ro ~/eslint.config.js \
			--env HOME \
			--env PATH \
			--env NVIM_RPLUGIN_MANIFEST \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env TERM \
			--env LANG \
	'';

	runInLandRunWithNet =''
		${runInLandRun} \
			--connect-tcp 443 \
			--env AWS_REGION \
			--env AWS_ACCESS_KEY_ID \
			--env AWS_SECRET_ACCESS_KEY \
			--env AWS_SESSION_TOKEN \
	'';

	makeWrapper = {landRun}: ''
export PATH="${
	pkgs.lib.makeBinPath ([
		pkgs.lua-language-server
		pkgs.typescript-language-server
		pkgs.bash
		pkgs.nodejs_24
		pkgs.git
		pkgs.ripgrep
		pkgs.tmux
		pkgs.man
		pkgs.eslint
		pkgs.vscode-langservers-extracted
		pkgs.rust-analyzer
		pkgs.yaml-language-server
		pkgs.bash-language-server
		pkgs.dockerfile-language-server-nodejs
		pkgs.marksman
		pkgs.terraform-ls
		pkgs.nixd
	])
}"

export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

NVIM_RPLUGIN_MANIFEST=${./rplugin.vim} ${landRun} \
${pkgs.neovim-unwrapped}/bin/nvim \
-u ${./init.lua} \
--cmd 'set packpath^=${packpath} | set runtimepath^=${packpath}' "$@"

	'';

	nvim = pkgs.writeShellScriptBin "nvim" (makeWrapper {landRun = runInLandRun;});
	nvim_net = pkgs.writeShellScriptBin "nvim-net" (makeWrapper {landRun = runInLandRunWithNet;});

	res = pkgs.symlinkJoin {
		name = "nvim-custom";
		paths = [nvim nvim_net];
	};
in
	res

