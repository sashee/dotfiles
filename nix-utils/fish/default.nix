{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	lazygit = (import ../lazygit {inherit pkgs;});
	nvim = (import ../nvim {inherit pkgs;});
	aws = (import ../aws {inherit pkgs;});
	npm = (import ../npm {inherit pkgs;});

	runInLandRun =''
		${lazygit.landrun_setup}
		${nvim.landrun_setup}
		${aws.landrun_setup}
		${npm.landrun_setup}

		RESTRICT_TO=$(${utils.findGitRoot}/bin/findGitRoot)

		echo "Restricting to folder: $RESTRICT_TO"

		${pkgs.landrun}/bin/landrun \
			--rwx /usr,/dev,/nix,/etc,/run,/proc \
			--rwx ''$RESTRICT_TO \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro ~/.gitconfig \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--rwx ~/.local/share/fish \
			--bind-tcp 8000 \
\
			${lazygit.landrun_requirements} \
			${nvim.landrun_requirements} \
			${aws.landrun_requirements} \
			${npm.landrun_requirements} \
			--rwx ~/.cache \
	'';

	makeWrapper = {landRun}: ''

export XDG_CONFIG_HOME=$(${pkgs.coreutils}/bin/mktemp -d)

${pkgs.coreutils}/bin/mkdir -p $XDG_CONFIG_HOME/fish
${pkgs.coreutils}/bin/ln -s ${./config_base/fish/config.fish} $XDG_CONFIG_HOME/fish/config.fish
${pkgs.coreutils}/bin/ln -s ${./config_base/fish/functions} $XDG_CONFIG_HOME/fish/functions

${landRun} \
${pkgs.fish}/bin/fish "$@"
	'';

	fish = pkgs.writeShellScriptBin "fish" (makeWrapper {landRun = runInLandRun;});
	#fish = pkgs.writeShellScriptBin "fish" (makeWrapper {landRun = '''';});
	fish_strace = pkgs.writeShellScriptBin "fish-strace" (makeWrapper {landRun = runInLandRun + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';});
in
	[
		fish
		fish_strace
	]

