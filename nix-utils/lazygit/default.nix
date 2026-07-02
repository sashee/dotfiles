{
	pkgs,
	git,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	# The sandboxed, hardened `git` tool (its launcher applies the git-exec
	# hardening; lazygit's own sandbox contains anything git triggers).
	gitBin = builtins.elemAt git.scripts 0;
	# Extend git's restrictions (gitconfig/ssh/network) with lazygit's own dirs,
	# the same way zsh merges its programs' restrictions.
	sandbox_restrictions = git.sandbox_restrictions // {
		fs = (git.sandbox_restrictions.fs or {}) // {
			"$HOME/.config/lazygit" = { perm = "rw"; mkdir = true; };
			"$HOME/.local/state/lazygit" = { perm = "rw"; mkdir = true; };
		};
	};
	bin = launcher.mkLauncher {
		name = "lazygit";
		target = "${pkgs.lazygit}/bin/lazygit";
		keepEnv = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK"];
		setEnv = {
			PATH = pkgs.lib.makeBinPath [
				gitBin
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
