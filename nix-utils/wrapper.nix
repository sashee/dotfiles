{pkgs, name, landrun_restrictions, landrun_setup, before, bin, generate_unsafe ? true, restrict_to_current_folder ? true}:
let
	utils = import ./utils.nix {inherit pkgs;};
	consts = import ./consts.nix;

	runInLandRun =''
	${landrun_setup}

${if restrict_to_current_folder then ''
set -x ${consts.RESTRICT_TO_ENV_VAR_NAME} $(${utils.findGitRoot}/bin/findGitRoot)

echo "[${bin}] Restricting to folder: ''$${consts.RESTRICT_TO_ENV_VAR_NAME}" >&2
'' else ''''}

function pass_all_env_variables
	for i in $(set -gx --names);
		echo -n -- "--env $i ";
	end
end

		${pkgs.landrun}/bin/landrun \
${builtins.concatStringsSep " " [
"--best-effort"
(if restrict_to_current_folder then ''--rwx ''$${consts.RESTRICT_TO_ENV_VAR_NAME}'' else '''')
(if
	(builtins.hasAttr "fs" landrun_restrictions) then
	(builtins.concatStringsSep " " (map (n: ''--${builtins.getAttr n landrun_restrictions.fs} ${n}'') (builtins.attrNames landrun_restrictions.fs)))
	else "--unrestricted-filesystem"
)
(if
	(builtins.hasAttr "env" landrun_restrictions) then
	(builtins.concatStringsSep " " (map (n: ''--env ${n}'') landrun_restrictions.env)) else
	''(string split " " -- (string trim -- (pass_all_env_variables)))''
)
"--env ${consts.SKIP_SANDBOX_ENV_VAR_NAME}"
(if
	(builtins.hasAttr "network" landrun_restrictions) then
	(if (builtins.hasAttr "tcp" landrun_restrictions.network) then
		''${builtins.concatStringsSep " " (
			builtins.concatLists [
				(if (builtins.hasAttr "connect" landrun_restrictions.network.tcp) then (map (port: "--connect-tcp ${builtins.toString port}") landrun_restrictions.network.tcp.connect) else [])
				(if (builtins.hasAttr "bind" landrun_restrictions.network.tcp) then (map (port: "--bind-tcp ${builtins.toString port}") landrun_restrictions.network.tcp.bind) else [])
			]
		)}''
		else "")
	else "--unrestricted-network"
)

]} \
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
		inherit scripts;
	}

