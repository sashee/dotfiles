{pkgs, name, sandbox_restrictions, sandbox_setup, before, bin, generate_unsafe ? true, restrict_to_current_folder ? true}:
let
  utils = import ./utils.nix {inherit pkgs;};
  consts = import ./consts.nix;

  runInBwrap = ''
    ${sandbox_setup}

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
      (builtins.hasAttr "network" sandbox_restrictions) && sandbox_restrictions.network then
      ''
--share-net \
			''
      else
      ""
    }\
--ro-bind / / \
--tmpfs /home \
${if (builtins.hasAttr "mount_dev" sandbox_restrictions) && sandbox_restrictions.mount_dev then "--dev-bind /dev /dev" else "--dev /dev"} \
--proc /proc \
--tmpfs /tmp \
(if set -q TMPDIR; and test -n "$TMPDIR"; and test "$TMPDIR" != "/tmp"; echo "--tmpfs $TMPDIR"; end) \
    ${if restrict_to_current_folder then ''--bind "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" \
'' else ""}\
    ${if
      (builtins.hasAttr "fs" sandbox_restrictions) then
      builtins.concatStringsSep "" (map (n:
        let perm = builtins.getAttr n sandbox_restrictions.fs; in
        if perm == "ro" then
          ''--ro-bind ${n} ${n} \
''
        else
          ''--bind ${n} ${n} \
''
      ) (builtins.attrNames sandbox_restrictions.fs))
      else ""
    }\
    ${if
      (builtins.hasAttr "files" sandbox_restrictions) then
      builtins.concatStringsSep "" (map (dest:
        let src = builtins.getAttr dest sandbox_restrictions.files; in
          ''--ro-bind ${src} ${dest} \
''
      ) (builtins.attrNames sandbox_restrictions.files))
      else ""
    }\
    ${if
      (builtins.hasAttr "env" sandbox_restrictions) then
      ''--clearenv \
'' + builtins.concatStringsSep "" (map (n: ''--setenv "${n}" "''$${n}" \
'' ) sandbox_restrictions.env)
      else ""
    }\
${if (builtins.hasAttr "allow_nested_sandbox" sandbox_restrictions) && sandbox_restrictions.allow_nested_sandbox then "" else ''--setenv "${consts.SKIP_SANDBOX_ENV_VAR_NAME}" "''$${consts.SKIP_SANDBOX_ENV_VAR_NAME}" \
''}\
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
    (pkgs.writeScriptBin "${name}-strace" (makeWrapper {inherit bin; bwrapCmd = ''
    ${pkgs.coreutils}/bin/touch /tmp/strace.log
    '' + runInBwrap + '' --bind /tmp/strace.log /tmp/strace.log ${pkgs.strace}/bin/strace -f -e trace=%network,%file,%desc,%process -s 2000 -yy -o /tmp/strace.log '';}))
    (pkgs.writeScriptBin "${name}-debug" (makeWrapper {bin = "${pkgs.bash}/bin/bash"; bwrapCmd = runInBwrap + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
    (pkgs.writeScriptBin "${name}-ranger" (makeWrapper {bin = "${pkgs.ranger}/bin/ranger"; bwrapCmd = runInBwrap;}))
  ] ++ (
    if generate_unsafe then [(pkgs.writeScriptBin "${name}-unsafe" (makeWrapper {inherit bin; bwrapCmd = "";}))] else []
  );
in
  {
    inherit scripts;
  }
