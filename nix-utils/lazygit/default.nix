{
	pkgs,
}:
let
	bin = "${pkgs.lazygit}/bin/lazygit";
	landrun_restrictions = {
		fs = {
			"~/.ssh/known_hosts" = "ro";
			"~/.gitconfig" = "ro";
			"~/.config/lazygit" = "rwx";
			"~/.local/state/lazygit" = "rwx";
			"$SSH_AUTH_SOCK" = "rwx";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK"];
		network = {};
	};
 	before = ''
export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.git
		pkgs.openssh
		pkgs.tree
	]
}"
	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/lazygit
	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "lazygit";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
