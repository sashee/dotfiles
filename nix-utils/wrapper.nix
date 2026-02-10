{pkgs, name, sandbox_restrictions, sandbox_setup, before, bin, generate_unsafe ? true, restrict_to_current_folder ? true}:
let
  utils = import ./utils.nix {inherit pkgs;};
  consts = import ./consts.nix;

  # Validate: error if a path appears in both fs and dbus
  validateNoConflicts = let
    fsPaths' = builtins.attrNames (sandbox_restrictions.fs or {});
    dbusPaths' = builtins.attrNames (sandbox_restrictions.dbus or {});
    conflicts = builtins.filter (p: builtins.elem p fsPaths') dbusPaths';
  in if conflicts == [] then true 
    else throw "Path(s) cannot be in both fs and dbus: ${builtins.concatStringsSep ", " conflicts}";

    # Always generate seccomp filter (no-op if no restrictions specified)
    seccompFilter = let
      baseSeccomp = sandbox_restrictions.seccomp or {};
      autoBlock = if !(sandbox_restrictions.network or false) then {
        AF_INET = true;
        AF_INET6 = true;
        AF_PACKET = true;
      } else {};
      mergedBlock = (baseSeccomp.block or {}) // autoBlock;
      seccompOptions = baseSeccomp // { block = mergedBlock; };
    in import ./seccomp.nix {
      inherit pkgs;
      options = seccompOptions;
    };

    # D-Bus proxy configuration
    dbusConfig = sandbox_restrictions.dbus or {};
    dbusPaths = builtins.attrNames dbusConfig;
    hasDbusProxy = dbusPaths != [];

    # Generate a variable name for each dbus path's proxy socket
    dbusProxyVarName = busPath: "__DBUS_PROXY_${builtins.hashString "md5" busPath}";
    dbusProxyPidVarName = busPath: "__DBUS_PROXY_PID_${builtins.hashString "md5" busPath}";

    # Generate the proxy startup script (fish shell)
    dbusProxyStartup = if !hasDbusProxy then "" else
      builtins.concatStringsSep "\n" (map (busPath:
        let
          cfg = dbusConfig.${busPath};
          talks = cfg.talk or [];
          owns = cfg.own or [];
          sees = cfg.see or [];
          calls = cfg.call or {};
          broadcasts = cfg.broadcast or {};
          log = cfg.log or false;
          
          socketVar = dbusProxyVarName busPath;
          pidVar = dbusProxyPidVarName busPath;
          
          talkArgs = builtins.concatStringsSep " " (map (n: "--talk=${n}") talks);
          ownArgs = builtins.concatStringsSep " " (map (n: "--own=${n}") owns);
          seeArgs = builtins.concatStringsSep " " (map (n: "--see=${n}") sees);
          callArgs = builtins.concatStringsSep " " (map (n: "--call=${n}=${calls.${n}}") (builtins.attrNames calls));
          broadcastArgs = builtins.concatStringsSep " " (map (n: "--broadcast=${n}=${broadcasts.${n}}") (builtins.attrNames broadcasts));
          logArg = if log then "--log" else "";
        in ''
    # Start D-Bus proxy for ${busPath}
    set -x ${socketVar} (${pkgs.coreutils}/bin/mktemp -u /tmp/dbus-proxy-XXXXXX)

    ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy \
      unix:path=${busPath} \
      ''$${socketVar} \
      --filter \
      ${logArg} \
      ${talkArgs} \
      ${ownArgs} \
      ${seeArgs} \
      ${callArgs} \
      ${broadcastArgs} \
      &
    set -x ${pidVar} $last_pid

    # Wait for proxy socket to be created
    while not test -e ''$${socketVar}
      ${pkgs.coreutils}/bin/sleep 0.01
    end
    echo "[${name}] D-Bus proxy for ${busPath} started at ''$${socketVar}" >&2
    ''
      ) dbusPaths);

    # Generate cleanup trap for proxy processes
    dbusProxyCleanup = if !hasDbusProxy then "" else
      let
        killCmds = builtins.concatStringsSep "\n    " (map (busPath:
          let
            pidVar = dbusProxyPidVarName busPath;
            socketVar = dbusProxyVarName busPath;
          in "kill $" + pidVar + " 2>/dev/null; ${pkgs.coreutils}/bin/rm -f $" + socketVar
        ) dbusPaths);
      in ''
    function __cleanup_dbus_proxies --on-event fish_exit
      ${killCmds}
    end
    '';

    # Generate bwrap arguments to bind proxy sockets and override env vars
    dbusProxyBwrapArgs = if !hasDbusProxy then "" else
      let
        # Bind proxy sockets to the original bus paths
        bindArgs = map (busPath:
          let socketVar = dbusProxyVarName busPath;
          in ''--bind ''$${socketVar} ${busPath}''
        ) dbusPaths;
      in
        builtins.concatStringsSep " \\\n" bindArgs;

    # Build bwrap arguments array outside of the string
    bwrapArgs = let
      # Create complete arguments array all at once, preserving exact order
      args = [
        # Namespace arguments (same order as current)
        (if (builtins.hasAttr "share_user" sandbox_restrictions) && sandbox_restrictions.share_user then "" else "--unshare-user --uid (${pkgs.coreutils}/bin/id -u) --gid (${pkgs.coreutils}/bin/id -g)")
        (if (builtins.hasAttr "share_uts" sandbox_restrictions) && sandbox_restrictions.share_uts then "" else "--unshare-uts")
        (if (builtins.hasAttr "share_cgroup" sandbox_restrictions) && sandbox_restrictions.share_cgroup then "" else "--unshare-cgroup-try")
        (if (builtins.hasAttr "share_pid" sandbox_restrictions) && sandbox_restrictions.share_pid then "" else "--unshare-pid")
        (if (builtins.hasAttr "share_ipc" sandbox_restrictions) && sandbox_restrictions.share_ipc then "" else "--unshare-ipc")
        (if (builtins.hasAttr "network" sandbox_restrictions) && sandbox_restrictions.network then "" else "--unshare-net")

        # Basic filesystem bindings
        (if (builtins.hasAttr "dont_die_with_parent" sandbox_restrictions) && sandbox_restrictions.dont_die_with_parent then "" else "--die-with-parent")
        "--ro-bind / /"
        "--tmpfs /home"
        (if (builtins.hasAttr "mount_dev" sandbox_restrictions) && sandbox_restrictions.mount_dev then "--dev-bind /dev /dev" else "--dev /dev")
        "--proc /proc"
        "--tmpfs /tmp"
        "(if set -q TMPDIR; and test -n \"$TMPDIR\"; and test \"$TMPDIR\" != \"/tmp\"; echo -- --tmpfs; echo -- \"$TMPDIR\"; end)"

        # Restrict to current folder
        (if restrict_to_current_folder then ''--bind "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" "''$${consts.RESTRICT_TO_ENV_VAR_NAME}"'' else "")

        # Protected path arguments (complex logic preserved exactly)
        (let
          # Convert path to relative subpath for lib.path.subpath.components
          # Handle ~ by treating it as a single component
          toSubpath = p:
            if pkgs.lib.hasPrefix "~" p then
              "./home/user" + builtins.substring 1 (-1) p
            else
              "." + p;
          pathDepth = p: builtins.length (pkgs.lib.path.subpath.components (toSubpath p));
          
          # Get explicit fs bindings from sandbox_restrictions
          explicitFs = if (builtins.hasAttr "fs" sandbox_restrictions) then sandbox_restrictions.fs else {};
          explicitPaths = builtins.attrNames explicitFs;
          
          # Paths covered by dbus proxy (these are handled separately via proxy)
          dbusProxyPaths = builtins.attrNames (sandbox_restrictions.dbus or {});
          
          # Protected paths that are NOT explicitly bound should be blocked
          # A protected path is "covered" if it or a parent path is in explicitPaths or dbusPaths
          isPathCovered = protected:
            builtins.any (explicit: 
              explicit == protected || pkgs.lib.hasPrefix (protected + "/") explicit || pkgs.lib.hasPrefix (explicit + "/") protected
            ) (explicitPaths ++ dbusProxyPaths);
          protectedToBlock = builtins.filter (p: !(isPathCovered p.path)) consts.protectedPaths;
          
          # Build combined entries: protected paths as "block", explicit paths as their permission
          # Also preserve the type from protectedPaths
          protectedEntries = map (p: { path = p.path; perm = "block"; type = p.type; }) protectedToBlock;
          explicitEntries = map (p: {
            path = p;
            perm = builtins.getAttr p explicitFs;
            # Look up type from protectedPaths, default to "dir"
            type = let
              matching = builtins.filter (pp: pp.path == p) consts.protectedPaths;
            in if matching == [] then "dir" else (builtins.head matching).type;
          }) explicitPaths;
          
          allEntries = protectedEntries ++ explicitEntries;
          
          # Deduplicate paths: group by path, prefer rw > ro > block
          groupedByPath = builtins.groupBy (e: e.path) allEntries;
          permPriority = perm: if perm == "rw" then 3 else if perm == "ro" then 2 else 1;
          deduplicatedEntries = map (path:
            let
              entries = builtins.getAttr path groupedByPath;
              # Pick highest priority permission
              sortedByPerm = builtins.sort (a: b: permPriority a.perm > permPriority b.perm) entries;
              winner = builtins.head sortedByPerm;
            in { inherit path; perm = winner.perm; type = winner.type; }
          ) (builtins.attrNames groupedByPath);
          
          # Sort by depth (shallow first)
          sortedEntries = builtins.sort (a: b: pathDepth a.path < pathDepth b.path) deduplicatedEntries;
        in
        builtins.concatStringsSep "" (map (entry:
          if entry.perm == "block" then
            # Block: use --tmpfs for dirs, --ro-bind /dev/null for files
            if entry.type == "dir" then
              ''(if test -e "${entry.path}"; echo -- --tmpfs; echo -- "${entry.path}"; end) \
''
            else
              ''(if test -e "${entry.path}"; echo -- --ro-bind; echo -- /dev/null; echo -- ${entry.path}; end) \
''
           else if entry.perm == "ro" then
             ''--ro-bind-try ${entry.path} ${entry.path} \
''
           else
             ''--bind-try ${entry.path} ${entry.path} \
''
        ) sortedEntries))

        # File bindings
        (if (builtins.hasAttr "files" sandbox_restrictions) then
          builtins.concatStringsSep "" (map (dest:
            let src = builtins.getAttr dest sandbox_restrictions.files; in
              ''--ro-bind-try ${src} ${dest} \
''
          ) (builtins.attrNames sandbox_restrictions.files))
        else "")

        # Environment variables
        (if (builtins.hasAttr "env" sandbox_restrictions) then
          ''--clearenv \
'' + builtins.concatStringsSep "" (map (n: ''--setenv "${n}" "''$${n}" \
'' ) (pkgs.lib.unique sandbox_restrictions.env))
        else "")

        # Final arguments
        (if (builtins.hasAttr "allow_nested_sandbox" sandbox_restrictions) && sandbox_restrictions.allow_nested_sandbox then "" else ''--setenv "${consts.SKIP_SANDBOX_ENV_VAR_NAME}" "''$${consts.SKIP_SANDBOX_ENV_VAR_NAME}" \
'')
        "--tmpfs /etc/ssh/ssh_config.d"
        "--seccomp 3"

        # D-Bus proxy socket bindings
        dbusProxyBwrapArgs
      ];

      # Filter out empty strings and join with proper formatting
      filteredArgs = builtins.filter (arg: arg != "") args;
      argsString = builtins.concatStringsSep " \\\n" filteredArgs;
    in
      argsString;

    # Import info script generation
    infoScript = import ./info.nix {
      inherit pkgs name sandbox_restrictions consts;
      makeWrapper = makeWrapper;
      runInBwrap = runInBwrap;
    };

   runInBwrap = ''
    ${sandbox_setup}

    ${dbusProxyCleanup}
    ${dbusProxyStartup}

    ${if restrict_to_current_folder then ''
    set -x ${consts.RESTRICT_TO_ENV_VAR_NAME} $(${utils.findGitRoot}/bin/findGitRoot)

    echo "[${bin}] Restricting to folder: ''$${consts.RESTRICT_TO_ENV_VAR_NAME}" >&2
    '' else ''''}

    ${pkgs.bubblewrap}/bin/bwrap \
    ${bwrapArgs} \
    '';

  makeWrapper = {bwrapCmd, bin}: ''
    #!${pkgs.fish}/bin/fish

    if set -q ${consts.SKIP_SANDBOX_ENV_VAR_NAME}; and test -n "''$${consts.SKIP_SANDBOX_ENV_VAR_NAME}"

      echo "[${bin}] Skipping sandbox as ${consts.SKIP_SANDBOX_ENV_VAR_NAME} is defined" >&2

      ${before}

      ${bin} $argv
    else
      ${before}

      ${bwrapCmd} \
      ${bin} $argv 3< ${seccompFilter}/filter.bpf
    end
    '';

   scripts = [
     (pkgs.writeScriptBin name (makeWrapper {inherit bin; bwrapCmd = runInBwrap;}))
     (pkgs.writeScriptBin "${name}-strace" (makeWrapper {inherit bin; bwrapCmd = ''
     ${pkgs.coreutils}/bin/touch /tmp/strace.log
     '' + runInBwrap + '' --bind /tmp/strace.log /tmp/strace.log ${pkgs.strace}/bin/strace -f -e trace=%network,%file,%desc,%process -s 2000 -yy -o /tmp/strace.log '';}))
     (pkgs.writeScriptBin "${name}-debug" (makeWrapper {bin = "${pkgs.bash}/bin/bash"; bwrapCmd = runInBwrap + '' ${pkgs.strace}/bin/strace -o /tmp/strace.log '';}))
     (pkgs.writeScriptBin "${name}-ranger" (makeWrapper {bin = "${pkgs.ranger}/bin/ranger"; bwrapCmd = runInBwrap;}))
     infoScript
   ] ++ (
     if generate_unsafe then [(pkgs.writeScriptBin "${name}-unsafe" (makeWrapper {inherit bin; bwrapCmd = "";}))] else []
   );
in
  assert validateNoConflicts;
  {
    inherit scripts;
  }
