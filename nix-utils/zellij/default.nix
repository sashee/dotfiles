{
	zsh,
	pkgs,
}:
let
	config = pkgs.writeTextFile {
		name = "config.kdl";
		text = ''
default_shell "${builtins.elemAt zsh.scripts 0}/bin/zsh"
show_startup_tips false
show_release_notes false
pane_frames false
default_mode "locked"

keybinds {
	normal {
		bind "Ctrl h" { GoToPreviousTab; }
		bind "Ctrl l" { GoToNextTab; }
	}
	shared_except "locked" {
		bind "Ctrl b" { SwitchToMode "Locked"; }
		bind "Alt n" { NewPane; SwitchToMode "Locked"; }
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
}
		'';
	};

	bin = "${pkgs.zellij}/bin/zellij --config ${config}";

	before = ''

	'';

	landrun_setup = zsh.landrun_setup or ''

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "zellij";
		inherit pkgs bin;
		landrun_restrictions = zsh.landrun_restrictions;
		inherit before landrun_setup;
	}).scripts;
	inherit (zsh) landrun_restrictions;
}
