{}:
let
  nixpkgs2 = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
  pkgs2 = import nixpkgs2 { config = {allowUnfree = true;}; overlays = [];};
in
import ../wrapper.nix {
	name = "github-copilot-cli";
	get_landrun_requirements = {pkgs}: ''
			--rox /usr,/dev,/nix,/run/systemd/resolve,/etc/passwd \
			--rwx /dev/null \
			--rwx (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end) \
			--ro /etc/ssl \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env SSL_CERT_FILE \
			--env LANG \
			--env TERM \
			--connect-tcp 443 \
	'';

	get_landrun_setup = {pkgs}: ''
	'';

	get_before = {pkgs}: ''
	'';

	get_bin = {pkgs}: "${pkgs2.github-copilot-cli}/bin/copilot";
}

