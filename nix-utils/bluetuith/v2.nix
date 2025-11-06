{
	pkgs,
}:
let
	bin = "${pkgs.bluetuith}/bin/bluetuith";
	landrun_restrictions = {
		network = {};
	};
	before = 
		let
			config = pkgs.runCommandLocal "config" {} ''
			mkdir -p $out/bluetuith
			touch $out/bluetuith/bluetuith.conf
			'';
		in
		''
		export XDG_CONFIG_HOME=${config}
		'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/bluetuith

	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "bluetuith";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}
