{
	pkgs,
}:
let
	launcher = import ../launcher.nix { inherit pkgs; };
	sandbox_restrictions = {
		network = false;
		seccomp = {
			block = {
				AF_UNIX = true;
			};
		};
	};
	bin = launcher.mkLauncher {
		name = "fx";
		target = "${pkgs.fx}/bin/fx";
		keepEnv = ["TERM" "HOME"];
	};
in
{
	scripts = (import ../_wrapper/default.nix {
		name = "fx";
		inherit pkgs bin sandbox_restrictions;
	}).scripts;
	inherit sandbox_restrictions;
}
