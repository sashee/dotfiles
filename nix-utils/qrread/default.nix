{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		fs = {
		};
		mount_dev = true;
	};
	target = pkgs.writeShellScript "qrread" ''
		${pkgs.zbar}/bin/zbarcam --nodisplay --oneshot --raw /dev/video0
		echo ""
	'';
	bin = launcher.mkLauncher {
		name = "qrread";
		target = "${target}";
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "qrread";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}

