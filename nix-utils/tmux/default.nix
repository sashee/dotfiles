{fish}:
let
	wrapper = import ../wrapper.nix;

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs.tmux}/bin/tmux -f ${./tmux.config}";
in
[
	(wrapper {
		name = "tmux";
		get_landrun_requirements = {pkgs}: ((builtins.head fish) {inherit pkgs;}).landrun_requirements;
		get_landrun_setup = {pkgs}: ((builtins.head fish) {inherit pkgs;}).landrun_setup;
		inherit get_before get_bin;
	})
]

