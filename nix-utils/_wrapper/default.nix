{ pkgs, name, sandbox_restrictions, bin, generate_unsafe ? true, restrict_to_current_folder ? true, quiet ? false, preLaunchHostCmd ? "" }:
let
  debugLogDir = "/tmp/nix-utils-debug";
  consts = import ../consts.nix;
  runner = import ./runner/default.nix { inherit pkgs; };
  binPath = bin.path;
  debugLauncher =
    bin.override (_: {
      name = "${name}-debug-shell";
      target = "${pkgs.bash}/bin/bash";
      extraArgs = [];
    });
  debugBinPath = debugLauncher.path;
  launcherArgsFile = pkgs.writeText "${name}-launcher-args.json" (builtins.toJSON bin.args);
  sandboxRestrictionsFile = pkgs.writeText "${name}-sandbox-restrictions.json" (builtins.toJSON sandbox_restrictions);
  runnerConfigFile = pkgs.writeText "${name}-runner-config.json" (mkRunnerConfig {
    commandString = binPath;
  });

  validateNoConflicts = let
    fsPaths' = builtins.attrNames (sandbox_restrictions.fs or {});
    dbusPaths' = builtins.attrNames (sandbox_restrictions.dbus or {});
    conflicts = builtins.filter (p: builtins.elem p fsPaths') dbusPaths';
  in if conflicts == [] then true
    else throw "Path(s) cannot be in both fs and dbus: ${builtins.concatStringsSep ", " conflicts}";

  afMap = {
    AF_INET = 2;
    AF_INET6 = 10;
    AF_UNIX = 1;
    AF_NETLINK = 16;
    AF_PACKET = 17;
    AF_BLUETOOTH = 31;
  };

  baseSeccomp = sandbox_restrictions.seccomp or {};
  autoBlock = if !(sandbox_restrictions.network or false) then {
    AF_INET = true;
    AF_INET6 = true;
    AF_PACKET = true;
  } else {};
  mergedSeccompBlock = (baseSeccomp.block or {}) // autoBlock;
  blockedSocketFamilies = builtins.map (name: afMap.${name}) (
    builtins.filter (name: mergedSeccompBlock.${name} or false) (builtins.attrNames afMap)
  );

  dbusConfig = sandbox_restrictions.dbus or {};
  dbusPaths = builtins.attrNames dbusConfig;

  explicitFs = sandbox_restrictions.fs or {};
  explicitPaths = builtins.attrNames explicitFs;

	isPathCovered = protected:
		builtins.elem protected (explicitPaths ++ dbusPaths);

  protectedToBlock = builtins.filter (p: !(isPathCovered p.path)) consts.protectedPaths;

  protectedEntries = map (p: {
    path = p.path;
    perm = "block";
    type = p.type;
    source = null;
  }) protectedToBlock;

  explicitEntries = map (p:
    let
      entry = builtins.getAttr p explicitFs;
    in {
      path = p;
      perm = entry.perm;
      type = entry.type or (let
        matching = builtins.filter (pp: pp.path == p) consts.protectedPaths;
      in if matching == [] then "dir" else (builtins.head matching).type);
      source = null;
      mkdir = entry.mkdir or false;
  }) explicitPaths;

  fileEntries = map (dest: {
    path = dest;
    perm = "ro";
    type = "file";
    source = builtins.getAttr dest (sandbox_restrictions.files or {});
    mkdir = false;
  }) (builtins.attrNames (sandbox_restrictions.files or {}));

  allEntries = protectedEntries ++ explicitEntries ++ fileEntries;
  groupedByPath = builtins.groupBy (e: e.path) allEntries;
  permPriority = perm: if perm == "rw" then 3 else if perm == "ro" then 2 else 1;

  deduplicatedEntries = map (path:
    let
      entries = builtins.getAttr path groupedByPath;
      sortedByPerm = builtins.sort (a: b: permPriority a.perm > permPriority b.perm) entries;
      winner = builtins.head sortedByPerm;
    in {
      inherit path;
      perm = winner.perm;
      type = winner.type;
      source = winner.source;
      mkdir = winner.mkdir or false;
    }
  ) (builtins.attrNames groupedByPath);

  pathDepth = p: builtins.length (builtins.filter (x: x != "") (pkgs.lib.splitString "/" p));
  mountRules = builtins.sort (a: b: pathDepth a.path < pathDepth b.path) deduplicatedEntries;

  devConfig = sandbox_restrictions.dev or false;
  useRealDev = devConfig != false;

  bwrapBaseArgs =
    (pkgs.lib.optionals (!((sandbox_restrictions.share_user or false))) [ "--unshare-user" "--uid" "__CURRENT_UID__" "--gid" "__CURRENT_GID__" ])
    ++ (pkgs.lib.optionals (!((sandbox_restrictions.share_uts or false))) [ "--unshare-uts" ])
    ++ (pkgs.lib.optionals (!((sandbox_restrictions.share_cgroup or false))) [ "--unshare-cgroup-try" ])
    ++ (pkgs.lib.optionals (!((sandbox_restrictions.share_pid or false))) [ "--unshare-pid" ])
    ++ (pkgs.lib.optionals (!((sandbox_restrictions.share_ipc or false))) [ "--unshare-ipc" ])
    ++ (pkgs.lib.optionals (!((sandbox_restrictions.network or false))) [ "--unshare-net" ])
    ++ (pkgs.lib.optionals (!((sandbox_restrictions.dont_die_with_parent or false))) [ "--die-with-parent" ])
    ++ [
      "--ro-bind" "/" "/"
      "--tmpfs" "/home"
    ]
    ++ (if useRealDev
      then [ "--dev-bind" "/dev" "/dev" ]
      else [ "--dev" "/dev" ])
    ++ [
		"--proc" "/proc"
		"--tmpfs" "/tmp"
	];

  mkRunnerConfig = {
    commandString,
    extraBwrapArgs ? [],
    extraMountRules ? [],
    debugBwrap ? false,
  }:
    builtins.toJSON {
      program_name = name;
      bwrap = {
        bin = "${pkgs.bubblewrap}/bin/bwrap";
        args = bwrapBaseArgs ++ extraBwrapArgs;
        add_tmpdir_tmpfs = true;
      };
      command = {
        bin = "${pkgs.bash}/bin/bash";
        args = [ "--noprofile" "--norc" "-c" "${commandString} \"$@\"" "--" ];
      };
      mounts = mountRules ++ extraMountRules;
      seccomp = {
        blocked_socket_families = blockedSocketFamilies;
      };
      debug_bwrap = debugBwrap;
      dev = devConfig;
      fake_dev_entries = consts.fakeDevEntries;
      dbus = {
        proxy_bin = "${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy";
        proxies = map (busPath:
          let cfg = dbusConfig.${busPath};
          in {
            source_bus_path = busPath;
            proxy_socket_path = null;
            talk = cfg.talk or [];
            own = cfg.own or [];
            see = cfg.see or [];
            call = cfg.call or {};
            broadcast = cfg.broadcast or {};
            log = cfg.log or false;
          }
        ) dbusPaths;
      };
      restrict_to_git_root = restrict_to_current_folder;
      quiet = quiet;
      real_machine_id = sandbox_restrictions.real_machine_id or false;
      optional_env_vars = consts.optionalEnvVars;
    };

  mkRunScript = { commandString, configFile ? null, extraBefore ? "" }:
    ''
#!${pkgs.bash}/bin/bash
set -eo pipefail

if [ "$(${pkgs.coreutils}/bin/printenv ${consts.SKIP_SANDBOX_ENV_VAR_NAME} 2>/dev/null || true)" = "true" ]; then
  ${pkgs.lib.optionalString (!quiet) "echo \"[${name}] Skipping sandbox as ${consts.SKIP_SANDBOX_ENV_VAR_NAME}=true\" >&2"}
  ${extraBefore}
  __nix_utils_cmd=$(${pkgs.coreutils}/bin/cat <<'__NIX_UTILS_CMD__'
${commandString}
__NIX_UTILS_CMD__
)
  exec ${pkgs.bash}/bin/bash --noprofile --norc -c "$__nix_utils_cmd \"\$@\"" -- "$@"
else
  ${pkgs.coreutils}/bin/mkdir -p ${debugLogDir}
  ${extraBefore}
  ${if configFile == null then
    ''__nix_utils_cmd=$(${pkgs.coreutils}/bin/cat <<'__NIX_UTILS_CMD__'
${commandString}
__NIX_UTILS_CMD__
)
exec ${pkgs.bash}/bin/bash --noprofile --norc -c "$__nix_utils_cmd \"\$@\"" -- "$@"''
   else
    ''exec ${runner}/bin/nix-sandbox-runner --config ${configFile} -- "$@"''}
fi
'';

  mkWrappedScript = {
    scriptName,
    commandString,
    extraBwrapArgs ? [],
    extraMountRules ? [],
    extraBefore ? "",
    showRunnerConfig ? false,
  }:
    let
      configFile = pkgs.writeText "${scriptName}-runner-config.json" (mkRunnerConfig {
        inherit commandString extraBwrapArgs extraMountRules;
        debugBwrap = showRunnerConfig;
      });
      extraBeforeWithRunnerConfig = extraBefore + pkgs.lib.optionalString showRunnerConfig ''
echo "[${scriptName}] runner config:" >&2
${pkgs.jq}/bin/jq . ${configFile} >&2
'';
    in pkgs.writeScriptBin scriptName (mkRunScript {
      commandString = commandString;
      configFile = configFile;
      extraBefore = extraBeforeWithRunnerConfig;
    });

  makeWrapper = { bwrapCmd, bin }:
    let
      _ = bwrapCmd;
      configFile = pkgs.writeText "${name}-info-runner-config.json" (mkRunnerConfig {
        commandString = bin;
      });
    in mkRunScript {
      commandString = bin;
      inherit configFile;
    };

  runInBwrap = "";

  infoScript = import ../info.nix {
    inherit pkgs name sandbox_restrictions consts makeWrapper runInBwrap launcherArgsFile sandboxRestrictionsFile runnerConfigFile;
  };

  scripts = [
    (mkWrappedScript {
      scriptName = name;
      commandString = binPath;
      extraBefore = preLaunchHostCmd;
    })
    (mkWrappedScript {
      scriptName = "${name}-strace";
      commandString = "${pkgs.strace}/bin/strace -f -e trace=%network,%file,%desc,%process -s 2000 -yy -o ${debugLogDir}/${name}-strace.log ${binPath}";
      extraBwrapArgs = [ "--bind" debugLogDir debugLogDir ];
      extraBefore = ''
${pkgs.coreutils}/bin/mkdir -p ${debugLogDir}
: > ${debugLogDir}/${name}-strace.log
'';
    })
    (mkWrappedScript {
      scriptName = "${name}-debug";
      commandString = "${pkgs.strace}/bin/strace -o ${debugLogDir}/${name}-strace.log ${debugBinPath}";
      extraBwrapArgs = [ "--bind" debugLogDir debugLogDir ];
      showRunnerConfig = true;
      extraBefore = ''
${pkgs.coreutils}/bin/mkdir -p ${debugLogDir}
: > ${debugLogDir}/${name}-strace.log
echo "[${name}-debug] launcher args:" >&2
${pkgs.jq}/bin/jq . ${launcherArgsFile} >&2
echo "[${name}-debug] sandbox restrictions:" >&2
${pkgs.jq}/bin/jq . ${sandboxRestrictionsFile} >&2
'';
    })
    (mkWrappedScript {
      # Like -debug (a bash shell in the tool's real sandbox, same env) but WITHOUT
      # strace: strace is ptrace-based and pathologically slow under aarch64 TCG
      # emulation, so tests that run a command in the sandbox use this instead.
      scriptName = "${name}-shell";
      commandString = debugBinPath;
    })
    (mkWrappedScript {
      scriptName = "${name}-ranger";
      commandString = "${pkgs.ranger}/bin/ranger";
    })
    infoScript
  ] ++ (
    if generate_unsafe then [
      (pkgs.writeScriptBin "${name}-unsafe" (mkRunScript {
        commandString = binPath;
        extraBefore = preLaunchHostCmd;
      }))
    ] else []
  );
in
  assert validateNoConflicts;
  {
    inherit scripts;
  }
