{prgs}:
import ../wrapper.nix {
	name = "fish";
	get_landrun_requirements = {pkgs}: ''
			--rwx /usr,/dev,/nix,/etc,/run,/proc,/sys \
			--rwx ''$RESTRICT_TO \
			--rwx "''${TMPDIR:-/tmp}" \
			--env HOME \
			--env PATH \
			--env TMPDIR \
			--env TERM \
			--env LANG \
			--env XDG_CONFIG_HOME \
			--env XDG_DATA_DIRS \
			--env XDG_RUNTIME_DIR \
			--rwx ~/.local/share/fish \
			--unrestricted-network \
			--bind-tcp 8000 \
			${pkgs.lib.strings.concatMapStringsSep "\\\n" (prg: prg.landrun_requirements) prgs} \
			--rwx ~/.cache \
	'';

	get_landrun_setup = {pkgs}: ''
		${pkgs.lib.strings.concatMapStringsSep "\n" (prg: prg.landrun_setup) prgs}
	'';

	get_before = {pkgs}: ''
export XDG_CONFIG_HOME=$(${pkgs.coreutils}/bin/mktemp -d)

${pkgs.coreutils}/bin/mkdir -p $XDG_CONFIG_HOME/fish
${pkgs.coreutils}/bin/ln -s ${./config.fish} $XDG_CONFIG_HOME/fish/config.fish
${pkgs.coreutils}/bin/ln -s ${./functions} $XDG_CONFIG_HOME/fish/functions
	'';

	get_bin = {pkgs}: "${pkgs.fish}/bin/fish";
}
