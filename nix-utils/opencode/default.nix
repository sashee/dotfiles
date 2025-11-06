{}:
let
  nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
  pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};

	config = pkgs2.writeTextFile {
		name = "opencode.conf";
		text = ''
{
  "$schema": "https://opencode.ai/schema.json",
  "provider": {
    "openrouter": {
			"model": {
				"gemini": {
					"provider": "openrouter",
					"model": "google/gemini-pro"
				}
			}
    }
  }
}
		'';
	};
in
import ../wrapper.nix {
	name = "opencode";
	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix,/run/systemd/resolve \
			--rox /proc \
			--rwx ~/.local/share/opencode \
			--rwx ~/.config/opencode \
			--rwx ~/.local/state/opencode \
			--rwx ~/.cache/opencode \
			--rwx /dev/null \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env LANG \
			--env TERM \
			--env OPENCODE_CONFIG \
			--unrestricted-network \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.local/share/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.local/state/opencode
		${pkgs.coreutils}/bin/mkdir -p ~/.cache/opencode
	'';

	get_before = {pkgs}: ''
export OPENCODE_CONFIG=${config}
	'';

	get_bin = {pkgs}: "/usr/bin/opencode";
}
