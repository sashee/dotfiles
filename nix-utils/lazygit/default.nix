{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	landrun_requirements = ''
			--rox /usr,/dev,/nix \
			--rwx /dev/null \
			--rwx /dev/ptmx \
			--rwx /dev/pts \
			--rwx /dev/tty \
			--rwx "''${TMPDIR:-/tmp}" \
			--ro /etc/ssl \
			--ro /etc \
			--ro $HOME/.ssh/known_hosts \
			--ro ~/.gitconfig \
			--rwx ~/.config/lazygit \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env SSH_AUTH_SOCK \
			--connect-tcp 22 \
	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/lazygit
	'';

	runInLandRun =''
	${landrun_setup}

		RESTRICT_TO=$(${utils.findGitRoot}/bin/findGitRoot)

		echo "Restricting to folder: $RESTRICT_TO"

		${pkgs.landrun}/bin/landrun \
			--rwx ''$RESTRICT_TO \
		${landrun_requirements} \
	'';

	makeWrapper = {landRun}: ''

export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.git
		pkgs.openssh
	]
}"
${landRun} \
${pkgs.lazygit}/bin/lazygit "$@"
	'';

	lazygit = pkgs.writeShellScriptBin "lazygit" (makeWrapper {landRun = runInLandRun;});
	lazygit_default = pkgs.writeShellScriptBin "lazygit-default" (makeWrapper {landRun = "";});
in
	{
		scripts = [
			lazygit
			lazygit_default
		];
		inherit landrun_requirements landrun_setup;
	}

