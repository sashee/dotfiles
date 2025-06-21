{name, get_landrun_requirements, get_landrun_setup, get_before, get_bin, generate_unsafe ? true}:
{
	pkgs
}:
let
	utils = import ./utils.nix {inherit pkgs;};
	landrun_setup = get_landrun_setup {inherit pkgs;};
	landrun_requirements = get_landrun_requirements {inherit pkgs;};
	before = get_before {inherit pkgs;};
	bin = get_bin {inherit pkgs;};

	runInLandRun =''
	${landrun_setup}

		RESTRICT_TO=$(${utils.findGitRoot}/bin/findGitRoot)

		echo "Restricting to folder: $RESTRICT_TO"

		${pkgs.landrun}/bin/landrun \
			--rwx ''$RESTRICT_TO \
		${landrun_requirements} \
	'';

	makeWrapper = {landRun}: ''

${before}
${landRun} \
${bin} "$@"
	'';

	scripts = [
		(pkgs.writeShellScriptBin name (makeWrapper {landRun = runInLandRun;}))
		(pkgs.writeShellScriptBin "${name}-strace" (makeWrapper {landRun = runInLandRun + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
	] ++ (
		if generate_unsafe then [(pkgs.writeShellScriptBin "${name}-unsafe" (makeWrapper {landRun = "";}))] else []
	);
in
	{
		inherit scripts landrun_requirements landrun_setup;
	}

