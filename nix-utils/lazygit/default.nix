{
	pkgs,
}:
let
	bin = "${pkgs.lazygit}/bin/lazygit";
	sandbox_restrictions = {
		fs = {
			"~/.ssh/known_hosts" = "ro";
			"~/.gitconfig" = "ro";
			"~/.config/lazygit" = "rw";
			"~/.local/state/lazygit" = "rw";
			"/run/user/1000/ssh-agent.socket" = "rw";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK"];
		network = true;
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

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/lazygit
	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "lazygit";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
