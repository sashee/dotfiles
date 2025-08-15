{}: (
import ../wrapper.nix {
	name = "lazygit";
	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix \
			--rwx /dev/null \
			--rwx /dev/ptmx \
			--rwx /dev/pts \
			--rwx /dev/tty \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--ro /etc/ssl \
			--ro /etc \
			--ro ~/.ssh/known_hosts \
			--ro ~/.gitconfig \
			--rwx ~/.config/lazygit \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env SSH_AUTH_SOCK \
			--connect-tcp 22 \
			--connect-tcp 443 \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/lazygit
	'';

	get_before = {pkgs}: ''
export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.git
		pkgs.openssh
	]
}"
	'';

	get_bin = {pkgs}: "${pkgs.lazygit}/bin/lazygit";
}
)
