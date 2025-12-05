{
	pkgs,
}:
let
	bin = "${pkgs.bluetuith}/bin/bluetuith";
	sandbox_restrictions = {
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

	sandbox_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/bluetuith

	'';
in
{
	scripts = (import ../wrapper.nix {
		name = "bluetuith";
		inherit pkgs bin sandbox_restrictions before sandbox_setup;
	}).scripts;
	inherit sandbox_restrictions;
}
