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
		decode_jwt() {
			token=$(printf '%s' "$1" | tr -d '[:space:]')
			exec ${pkgs.jwt-cli}/bin/jwt decode --date "$token"
		}

		if [ "$#" -gt 0 ]; then
			decode_jwt "$*"
		fi

		buffer=""
		while IFS= read -r line; do
			buffer="$buffer$line"
			candidate=$(printf '%s' "$buffer" | tr -d '[:space:]')
			if ${pkgs.jwt-cli}/bin/jwt decode --date "$candidate" >/dev/null 2>&1; then
				decode_jwt "$buffer"
			fi
		done

		echo "The JWT provided is invalid" >&2
		exit 1
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
