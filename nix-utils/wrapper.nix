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
set -x ${consts.RESTRICT_TO_ENV_VAR_NAME} $(${utils.findGitRoot}/bin/findGitRoot)

echo "[${bin}] Restricting to folder: ''$${consts.RESTRICT_TO_ENV_VAR_NAME}" >&2
'' else ''''}

		${pkgs.landrun}/bin/landrun \
${if restrict_to_current_folder then ''--rwx ''$${consts.RESTRICT_TO_ENV_VAR_NAME}'' else ''''} \
			--env ${consts.SKIP_SANDBOX_ENV_VAR_NAME} \
		${landrun_requirements} \
	'';

	makeWrapper = {landRun, bin}: ''
#!${pkgs.fish}/bin/fish

if set -q ${consts.SKIP_SANDBOX_ENV_VAR_NAME}

	echo "[${bin}] Skipping sandbox as ${consts.SKIP_SANDBOX_ENV_VAR_NAME} is defined" >&2

	${before}

	${bin} $argv
else
	${before}

	${landRun} \
	${bin} $argv
end
	'';

	scripts = [
		(pkgs.writeScriptBin name (makeWrapper {inherit bin; landRun = runInLandRun;}))
		(pkgs.writeScriptBin "${name}-strace" (makeWrapper {inherit bin; landRun = runInLandRun + '' ${pkgs.strace}/bin/strace -f -o (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end)/strace.log '';}))
		(pkgs.writeScriptBin "${name}-debug" (makeWrapper {bin = "${pkgs.bash}/bin/bash"; landRun = runInLandRun + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
	] ++ (
		if generate_unsafe then [(pkgs.writeScriptBin "${name}-unsafe" (makeWrapper {inherit bin; landRun = "";}))] else []
	);
in
	{
		inherit scripts landrun_requirements landrun_setup name;
	}

