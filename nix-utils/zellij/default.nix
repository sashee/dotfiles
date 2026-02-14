{
	zsh,
	pkgs,
	nvim,
}:
let
	consts = import ../consts.nix;
	launcher = import ../launcher.nix { inherit pkgs; };
	config = pkgs.writeTextFile {
		name = "config.kdl";
		text = ''
default_shell "${builtins.elemAt zsh.scripts 0}/bin/zsh"
show_startup_tips false
show_release_notes false
pane_frames false
default_mode "locked"
scroll_buffer_size 100000
scrollback_editor "${builtins.elemAt nvim.scripts 0}/bin/nvim"

keybinds {
	normal {
		bind "Ctrl h" { GoToPreviousTab; }
		bind "Ctrl l" { GoToNextTab; }
	}
	shared_except "locked" {
		bind "Ctrl b" { SwitchToMode "Locked"; }
		unbind "Ctrl g"
		unbind "Ctrl q"
	}
	pane {
		bind "n" { NewPane; SwitchToMode "Locked"; }
	}
	locked {
		bind "Ctrl h" { GoToPreviousTab; }
		bind "Ctrl l" { GoToNextTab; }
		bind "Ctrl b" { SwitchToMode "Normal"; }
	}
	search {
		bind "N" { Search "up"; }
	}
	tab {
		bind "n" { NewTab; SwitchToMode "Locked"; }
	}
	scroll {
		bind "e" { EditScrollback; SwitchToMode "Locked"; }
	}
}
		'';
	};

	bin = launcher.mkLauncher {
		name = "zellij";
		target = "${pkgs.zellij}/bin/zellij";
		extraArgs = [ "--config" "${config}" ];
		setEnv = {
			"${consts.SKIP_SANDBOX_ENV_VAR_NAME}" = "false";
		};
	};

	merged_sandbox_restrictions = zsh.sandbox_restrictions // {
		dont_die_with_parent = true;
		share_pid = true;
		fs = (zsh.sandbox_restrictions.fs or {}) // {
			"/run/user/1000" = { perm = "rw"; };
			"$HOME/.cache/zellij" = { perm = "rw"; mkdir = true; };
		};
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "zellij";
		inherit pkgs bin;
		sandbox_restrictions = merged_sandbox_restrictions // {
			network = true;
		};
	}).scripts;
	sandbox_restrictions = merged_sandbox_restrictions;
}
