{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"$HOME/.ssh/known_hosts" = { perm = "ro"; };
			"$HOME/.gitconfig" = { perm = "ro"; };
			"$HOME/.config/lazygit" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/state/lazygit" = { perm = "rw"; };
			"$SSH_AUTH_SOCK" = { perm = "rw"; };
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
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "lazygit";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
