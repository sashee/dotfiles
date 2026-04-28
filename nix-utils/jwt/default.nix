{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
		sandbox_restrictions = {
			fs = {
			};
		};
	target = pkgs.writeShellScript "jwt" ''
		${pkgs.jwt-cli}/bin/jwt decode --date "$@"
	'';
	bin = launcher.mkLauncher {
		name = "jwt";
		target = "${target}";
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "jwt";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}

