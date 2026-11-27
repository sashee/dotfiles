# Agent skills (SKILL.md folders), shared by every coding agent in nix-utils.
#
# Builds ONE read-only bundle in the Claude Code plugin layout:
#   $out/.claude-plugin/plugin.json
#   $out/skills/<name>/SKILL.md (+ the skill's supporting files)
# so each agent is pointed at it through its own config, and nothing is written into
# $HOME (no `claude plugin install`, no `npx skills add`):
#   - claude:   --plugin-dir ${bundle}           -> skills appear as /nix-utils-skills:<name>
#   - opencode: "skills": ["${bundle}/skills"]   (opencode.json)
#   - others:   anything that reads a flat <dir>/<name>/SKILL.md tree (e.g. ~/.agents/skills)
#
# Sources are pinned on purpose: skills are prompts the agents run under
# bypassPermissions, so review the upstream diff before bumping rev + hash
# (e.g. `nurl https://github.com/mattpocock/skills <rev>`).
{ pkgs }:
let
	# https://github.com/mattpocock/skills. Only upstream's curated set is taken: the
	# paths in its own .claude-plugin/plugin.json `skills` array (which leaves out
	# misc/, in-progress/ and deprecated/), so there is no hand-kept list to drift.
	mattpocock = pkgs.fetchFromGitHub {
		owner = "mattpocock";
		repo = "skills";
		rev = "6f7f7831a625f040a8e06a0e7954826b87ce775a";
		hash = "sha256-kM/OK6+kbTHzlN5d6wjL9hM80lolcSCoO8A1oRvEJEU=";
	};

	pluginJson = pkgs.writeText "plugin.json" (builtins.toJSON {
		name = "nix-utils-skills";
		version = "0.0.0";
		description = "Agent skills bundled by nix-utils";
	});
in
pkgs.runCommand "agent-skills" { nativeBuildInputs = [ pkgs.jq ]; } ''
	mkdir -p $out/.claude-plugin $out/skills
	cp ${pluginJson} $out/.claude-plugin/plugin.json

	while read -r path; do
		name=$(basename "$path")
		if [ -e "$out/skills/$name" ]; then
			echo "agent-skills: duplicate skill name '$name'" >&2
			exit 1
		fi
		cp -r ${mattpocock}/"$path" "$out/skills/$name"
		test -f "$out/skills/$name/SKILL.md"
	done < <(jq -r '.skills[]' ${mattpocock}/.claude-plugin/plugin.json)

	# An upstream layout change must fail the build, not ship an empty bundle.
	test -n "$(ls $out/skills)"
''
