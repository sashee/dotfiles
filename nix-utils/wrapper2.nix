{pkgs, name, landrun_restrictions, landrun_setup, before, bin, generate_unsafe ? true, restrict_to_current_folder ? true}:
let
  utils = import ./utils.nix {inherit pkgs;};
  consts = import ./consts.nix;

  runInBwrap = ''
    ${landrun_setup}

    ${if restrict_to_current_folder then ''
    set -x ${consts.RESTRICT_TO_ENV_VAR_NAME} $(${utils.findGitRoot}/bin/findGitRoot)

    echo "[${bin}] Restricting to folder: ''$${consts.RESTRICT_TO_ENV_VAR_NAME}" >&2
    '' else ''''}

    ${pkgs.bubblewrap}/bin/bwrap \
--unshare-all \
--die-with-parent \
--uid (${pkgs.coreutils}/bin/id -u) \
--gid (${pkgs.coreutils}/bin/id -g) \
    ${if
      (builtins.hasAttr "network" landrun_restrictions) then
      ''
--share-net \
			''
      else
      ""
    }\
--ro-bind / / \
--tmpfs /home \
--dev /dev \
--proc /proc \
--tmpfs /tmp \
(if set -q TMPDIR; and test "$TMPDIR" != "/tmp"; echo "--tmpfs $TMPDIR"; end) \
    ${if restrict_to_current_folder then ''--bind "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" \
'' else ""}\
    ${if
      (builtins.hasAttr "fs" landrun_restrictions) then
      builtins.concatStringsSep "" (map (n:
        let perm = builtins.getAttr n landrun_restrictions.fs; in
        if perm == "ro" || perm == "rox" then
          ''--ro-bind ${n} ${n} \
''
        else
          ''--bind ${n} ${n} \
''
      ) (builtins.attrNames landrun_restrictions.fs))
      else ""
    }\
    ${if
      (builtins.hasAttr "env" landrun_restrictions) then
      ''--clearenv \
'' + builtins.concatStringsSep "" (map (n: ''--setenv "${n}" "''$${n}" \
'' ) landrun_restrictions.env)
      else ""
    }\
    --setenv "${consts.SKIP_SANDBOX_ENV_VAR_NAME}" "''$${consts.SKIP_SANDBOX_ENV_VAR_NAME}" \
--tmpfs /etc/ssh/ssh_config.d \
    '';

  makeWrapper = {bwrapCmd, bin}: ''
    #!${pkgs.fish}/bin/fish

    if set -q ${consts.SKIP_SANDBOX_ENV_VAR_NAME}

      echo "[${bin}] Skipping sandbox as ${consts.SKIP_SANDBOX_ENV_VAR_NAME} is defined" >&2

      ${before}

      ${bin} $argv
    else
      ${before}

      ${bwrapCmd} \
      ${bin} $argv
    end
    '';

  scripts = [
    (pkgs.writeScriptBin name (makeWrapper {inherit bin; bwrapCmd = runInBwrap;}))
    (pkgs.writeScriptBin "${name}-strace" (makeWrapper {inherit bin; bwrapCmd = runInBwrap + '' ${pkgs.strace}/bin/strace -f -e trace=%network,%file,%desc,%process -s 2000 -yy -o (if set -q TMPDIR; echo $TMPDIR; else; echo "/tmp"; end)/strace.log '';}))
    (pkgs.writeScriptBin "${name}-debug" (makeWrapper {bin = "${pkgs.bash}/bin/bash"; bwrapCmd = runInBwrap + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
    (pkgs.writeScriptBin "${name}-ranger" (makeWrapper {bin = "${pkgs.ranger}/bin/ranger"; bwrapCmd = runInBwrap;}))
  ] ++ (
    if generate_unsafe then [(pkgs.writeScriptBin "${name}-unsafe" (makeWrapper {inherit bin; bwrapCmd = "";}))] else []
  );
in
  {
    inherit scripts;
  }
