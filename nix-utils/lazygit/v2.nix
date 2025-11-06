{
	pkgs,
}:
let
	bin = "${pkgs.lazygit}/bin/lazygit";
	landrun_restrictions = {
		fs = {
			"/usr" = "rox";
			"/dev" = "rox";
			"/nix" = "rox";
			"/run/systemd/resolve" = "rox";
			"/dev/null" = "rwx";
			"/dev/ptmx" = "rwx";
			"/dev/pts" = "rwx";
			"/dev/tty" = "rwx";
			"(if set -q TMPDIR; echo $TMPDIR; else; echo \"/tmp\"; end)" = "rwx";
			"/etc/ssl" = "ro";
			"/etc" = "ro";
			"~/.ssh/known_hosts" = "ro";
			"~/.gitconfig" = "ro";
			"~/.config/lazygit" = "rwx";
		};
		env = ["HOME" "PATH" "TMPDIR" "TERM" "LANG" "SSH_AUTH_SOCK"];
		network = {
			tcp = {
				connect = [22 443];
			};
		};
	};
	before = ''
export PATH="${
	pkgs.lib.makeBinPath [
		pkgs.git
		pkgs.openssh
	]
}"
	'';

	landrun_setup = ''
		${pkgs.coreutils}/bin/mkdir -p ~/.config/lazygit
	'';
in
{
	scripts = (import ../wrapper2.nix {
		name = "lazygit";
		inherit pkgs bin landrun_restrictions before landrun_setup;
	}).scripts;
	inherit landrun_restrictions;
}