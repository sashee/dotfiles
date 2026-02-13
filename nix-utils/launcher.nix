{ pkgs }:
let
  skipSandboxEnvVar = "__NIX_UTILS_SKIP_SANDBOX";
  mkLauncher = args@{
    name,
    target,
    keepEnv ? null,
    setEnv ? {},
    extraArgs ? [],
  }:
    let
      effectiveSetEnv =
        if builtins.hasAttr skipSandboxEnvVar setEnv
          then setEnv
          else setEnv // { "${skipSandboxEnvVar}" = "true"; };
      effectiveKeepEnv =
        if keepEnv == null
          then null
          else pkgs.lib.unique (keepEnv ++ [ skipSandboxEnvVar ]);
      launcher = pkgs.writeShellScriptBin "${name}-launcher" ''
set -euo pipefail

${if effectiveKeepEnv == null then ''
env_args=()
'' else ''
env_args=(-i)

${pkgs.lib.concatMapStringsSep "\n" (v: ''
if [[ -v ${v} ]]; then
  env_args+=("${v}=$(${pkgs.coreutils}/bin/printenv ${v})")
fi
'') effectiveKeepEnv}
''}

${pkgs.lib.concatMapStringsSep "\n" (k:
  "env_args+=(${pkgs.lib.escapeShellArg "${k}=${effectiveSetEnv.${k}}"})"
) (builtins.attrNames effectiveSetEnv)}

exec ${pkgs.coreutils}/bin/env "''${env_args[@]}" ${pkgs.lib.escapeShellArg target} ${pkgs.lib.escapeShellArgs extraArgs} "$@"
'';
    in
      rec {
        path = "${launcher}/bin/${name}-launcher";
        override = f: mkLauncher (args // (f args));
      };
in {
  inherit mkLauncher;
}
