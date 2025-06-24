{name, get_landrun_requirements, get_landrun_setup, get_before, get_bin, generate_unsafe ? true, restrict_to_current_folder ? true}:
{
	pkgs
}:
let
	utils = import ./utils.nix {inherit pkgs;};
	consts = import ./consts.nix;
	landrun_setup = get_landrun_setup {inherit pkgs;};
	landrun_requirements = get_landrun_requirements {inherit pkgs;};
	before = get_before {inherit pkgs;};
	bin = get_bin {inherit pkgs;};

	runInLandRun =''
	${landrun_setup}

${if restrict_to_current_folder then ''
RESTRICT_TO=$(${utils.findGitRoot}/bin/findGitRoot)

echo "[${bin}] Restricting to folder: $RESTRICT_TO"
'' else ''''}

		${pkgs.landrun}/bin/landrun \
${if restrict_to_current_folder then ''--rwx ''$RESTRICT_TO'' else ''''} \
			--env ${consts.SKIP_SANDBOX_ENV_VAR_NAME} \
		${landrun_requirements} \
	'';

	makeWrapper = {landRun, bin}: ''

if [[ -z "''$${consts.SKIP_SANDBOX_ENV_VAR_NAME}" ]]; then

	${before}

	${landRun} \
	${bin} "$@"
else
	echo "[${bin}] Skipping sandbox as ${consts.SKIP_SANDBOX_ENV_VAR_NAME} is defined"

	${before}

	${bin} "$@"
fi
	'';

	scripts = [
		(pkgs.writeShellScriptBin name (makeWrapper {inherit bin; landRun = runInLandRun;}))
		(pkgs.writeShellScriptBin "${name}-strace" (makeWrapper {inherit bin; landRun = runInLandRun + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
		(pkgs.writeShellScriptBin "${name}-debug" (makeWrapper {bin = "${pkgs.bash}/bin/bash"; landRun = runInLandRun + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
	] ++ (
		if generate_unsafe then [(pkgs.writeShellScriptBin "${name}-unsafe" (makeWrapper {inherit bin; landRun = "";}))] else []
	);
in
	{
		inherit scripts landrun_requirements landrun_setup;
	}

