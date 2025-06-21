{
	pkgs,
}:
let
	findWorkspaceDirAndDefaultsToCurrent = pkgs.writeScriptBin "findWorkspaceDirAndDefaultsToCurrent" ''
#!${pkgs.nodePackages_latest.nodejs}/bin/node
import path from "node:path";

const workspaceDir = path.join(process.env.HOME, "workspace");

const relativeToWorkspace = path.relative(workspaceDir, process.cwd()).split(path.sep)[0];

if (relativeToWorkspace.startsWith(".")) {
	// not in workspace
	console.log(process.cwd());
}else {
	console.log(path.join(process.env.HOME, "workspace", relativeToWorkspace));
}
	'';

	findGitRoot = pkgs.writeScriptBin "findGitRoot" ''
#!${pkgs.nodePackages_latest.nodejs}/bin/node
import fs from "node:fs/promises";
import path from "node:path";

const parts = process.cwd().split(path.sep);
const res = await Promise.allSettled(parts.map(async (p, i, l) => {
	const constructedPath = l.slice(0, i + 1).join(path.sep);
	if (!path.isAbsolute(constructedPath)) {
		throw new Error("Not absolute, should be skipped");
	}
	await fs.access(path.join(constructedPath, ".git"), fs.constants.F_OK);
	return constructedPath;
}));
const mostSpecificRepo = res
	.filter(({status}) => status === "fulfilled")
	.toReversed()
	.map(({value}) => value)[0];

if (mostSpecificRepo) {
	// there is a repo somewhere, return that
	console.log(mostSpecificRepo);
}else {
	// no repo, restrict to current dir
	console.log(process.cwd());
}
	'';

	makeWrappedProgram = {name, landrun_requirements, landrun_setup, before, bin}:
{
	pkgs
}:
let

	runInLandRun =''
	${landrun_setup}

		RESTRICT_TO=$(${findGitRoot}/bin/findGitRoot)

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

	prg = pkgs.writeShellScriptBin name (makeWrapper {landRun = runInLandRun;});
	prg_default = pkgs.writeShellScriptBin "${name}-default" (makeWrapper {landRun = "";});
in
	{
		scripts = [
			prg
			prg_default
		];
		inherit landrun_requirements landrun_setup;
	}

;
in
	{
		inherit findWorkspaceDirAndDefaultsToCurrent findGitRoot makeWrappedProgram;
	}

