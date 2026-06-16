{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
			"$HOME/.ssh/known_hosts" = { perm = "ro"; };
			"$HOME/.gitconfig" = { perm = "ro"; };
			"$SSH_AUTH_SOCK" = { perm = "rw"; };
		};
		network = true;
	};
	bin = launcher.mkLauncher {
		name = "git";
		target = "${pkgs.git}/bin/git";
		keepEnv = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK"];
		# Disable git's fixed-name command-exec keys at command-line precedence
		# (beats repo-local .git/config). The attacker-named filter/textconv/merge
		# families have no global off-switch and are instead contained by the
		# sandbox below.
		setEnv = {
			GIT_CONFIG_COUNT = "5";
			GIT_CONFIG_KEY_0 = "core.hooksPath";            GIT_CONFIG_VALUE_0 = "/dev/null";
			GIT_CONFIG_KEY_1 = "core.fsmonitor";            GIT_CONFIG_VALUE_1 = "false";
			GIT_CONFIG_KEY_2 = "protocol.ext.allow";        GIT_CONFIG_VALUE_2 = "never";
			GIT_CONFIG_KEY_3 = "diff.external";             GIT_CONFIG_VALUE_3 = "";
			GIT_CONFIG_KEY_4 = "core.alternateRefsCommand"; GIT_CONFIG_VALUE_4 = "";
		};
	};
in
{
	# restrict_to_current_folder defaults true -> git is confined to the current
	# git root, so any git-triggered execution (filters/textconv/merge drivers a
	# malicious .git/config defines) runs only inside this sandbox, never on the
	# host.
	scripts = (import ../_wrapper/default.nix {
		name = "git";
		inherit pkgs bin sandbox_restrictions;
		quiet = true;
	}).scripts;
	inherit sandbox_restrictions;
}
