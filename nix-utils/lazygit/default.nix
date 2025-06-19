{
	pkgs
}:
let
	utils = import ../utils.nix {inherit pkgs;};

	runInLandRun =''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/lazygit

		echo "Restricting to folder: $(${utils.findGitRoot}/bin/findGitRoot)"

		${pkgs.landrun}/bin/landrun \
			--rox /usr,/dev,/nix \
			--rwx ''$(${utils.findGitRoot}/bin/findGitRoot) \
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
	[
		lazygit
		lazygit_default
	]


