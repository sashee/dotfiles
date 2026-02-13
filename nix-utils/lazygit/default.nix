{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"$HOME/.ssh/known_hosts" = "ro";
			"$HOME/.gitconfig" = "ro";
			"$HOME/.config/lazygit" = "rw";
			"$HOME/.local/state/lazygit" = "rw";
			"$SSH_AUTH_SOCK" = "rw";
		};
		network = true;
	};
	bin = launcher.mkLauncher {
		name = "lazygit";
		target = "${pkgs.lazygit}/bin/lazygit";
		keepEnv = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK"];
		setEnv = {
			PATH = pkgs.lib.makeBinPath [
				pkgs.git
				pkgs.openssh
				pkgs.tree
			];
		};
	};
	before = ''
	'';

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p $HOME/.config/lazygit
	'';
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "lazygit";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
