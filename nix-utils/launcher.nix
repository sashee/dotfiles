{ pkgs }:
let
  skipSandboxEnvVar = "__NIX_UTILS_SKIP_SANDBOX";
  # Escape a string for a bash double-quoted context, neutralising \ ` " but
  # deliberately leaving $ so $VAR/${VAR} still expand at launch.
  escapeDq = builtins.replaceStrings [ "\\" "`" "\"" ] [ "\\\\" "\\`" "\\\"" ];
  mkLauncher = launcherArgs@{
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
          else pkgs.lib.unique (keepEnv ++ [ "XDG_RUNTIME_DIR" "WAYLAND_DISPLAY" skipSandboxEnvVar ]);
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
  # Double-quoted so bash expands $VAR/${VAR} in the value. `set -euo pipefail`
  # makes a reference to an unset variable abort (fail-closed). setEnv values
  # are author-controlled.
  "env_args+=(\"${escapeDq k}=${escapeDq effectiveSetEnv.${k}}\")"
) (builtins.attrNames effectiveSetEnv)}

exec ${pkgs.coreutils}/bin/env "''${env_args[@]}" ${pkgs.lib.escapeShellArg target} ${pkgs.lib.escapeShellArgs extraArgs} "$@"
'';
    in
      rec {
        path = "${launcher}/bin/${name}-launcher";
        args = launcherArgs;
        override = f: mkLauncher (launcherArgs // (f launcherArgs));
      };
in {
  inherit mkLauncher;
}
