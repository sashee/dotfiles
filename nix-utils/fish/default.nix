{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	runInLandRun =''
		RESTRICT_TO=$(${utils.findGitRoot}/bin/findGitRoot)

		echo "Restricting to folder: $RESTRICT_TO"

		${pkgs.landrun}/bin/landrun \
			--rox /usr,/dev,/nix \
			--rwx ''$RESTRICT_TO \
			--rwx /dev/null \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro ~/.gitconfig \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env XDG_CONFIG_HOME \
\
			--rwx ~/.local/state/nvim \
			--rwx ~/.cache \
			--ro ~/eslint.config.js \
			--ro ~/.gitconfig \
	'';

	makeWrapper = {landRun}: ''

export XDG_CONFIG_HOME=${./config_base}

${landRun} \
${pkgs.fish}/bin/fish "$@"
	'';

	fish = pkgs.writeShellScriptBin "fish" (makeWrapper {landRun = runInLandRun;});
in
	[
		fish
	]



