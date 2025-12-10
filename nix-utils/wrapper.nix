{pkgs, name, sandbox_restrictions, sandbox_setup, before, bin, generate_unsafe ? true, restrict_to_current_folder ? true}:
let
  utils = import ./utils.nix {inherit pkgs;};
  consts = import ./consts.nix;

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

  runInBwrap = ''
    ${sandbox_setup}

    ${if restrict_to_current_folder then ''
    set -x ${consts.RESTRICT_TO_ENV_VAR_NAME} $(${utils.findGitRoot}/bin/findGitRoot)

    echo "[${bin}] Restricting to folder: ''$${consts.RESTRICT_TO_ENV_VAR_NAME}" >&2
    '' else ''''}

    ${pkgs.bubblewrap}/bin/bwrap \
${if (builtins.hasAttr "share_user" sandbox_restrictions) && sandbox_restrictions.share_user then "" else "--unshare-user --uid (${pkgs.coreutils}/bin/id -u) --gid (${pkgs.coreutils}/bin/id -g)"} \
${if (builtins.hasAttr "share_uts" sandbox_restrictions) && sandbox_restrictions.share_uts then "" else "--unshare-uts"} \
${if (builtins.hasAttr "share_cgroup" sandbox_restrictions) && sandbox_restrictions.share_cgroup then "" else "--unshare-cgroup-try"} \
${if (builtins.hasAttr "share_pid" sandbox_restrictions) && sandbox_restrictions.share_pid then "" else "--unshare-pid"} \
${if (builtins.hasAttr "share_ipc" sandbox_restrictions) && sandbox_restrictions.share_ipc then "" else "--unshare-ipc"} \
${if (builtins.hasAttr "network" sandbox_restrictions) && sandbox_restrictions.network then "" else "--unshare-net"} \
--die-with-parent \
--ro-bind / / \
--tmpfs /home \
${if (builtins.hasAttr "mount_dev" sandbox_restrictions) && sandbox_restrictions.mount_dev then "--dev-bind /dev /dev" else "--dev /dev"} \
--proc /proc \
--tmpfs /tmp \
(if set -q TMPDIR; and test -n "$TMPDIR"; and test "$TMPDIR" != "/tmp"; echo "--tmpfs $TMPDIR"; end) \
    ${if restrict_to_current_folder then ''--bind "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" "''$${consts.RESTRICT_TO_ENV_VAR_NAME}" \
'' else ""}\
    ${let
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
      
      # Protected paths that are NOT explicitly bound should be blocked
      # A protected path is "covered" if it or a parent path is in explicitPaths
      isPathCovered = protected:
        builtins.any (explicit: 
          explicit == protected || pkgs.lib.hasPrefix (protected + "/") explicit || pkgs.lib.hasPrefix (explicit + "/") protected
        ) explicitPaths;
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
          ''--tmpfs ${entry.path} \
''
        else
          ''--ro-bind /dev/null ${entry.path} \
''
      else if entry.perm == "ro" then
        ''--ro-bind ${entry.path} ${entry.path} \
''
      else
        ''--bind ${entry.path} ${entry.path} \
''
    ) sortedEntries)
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
'' ) (pkgs.lib.unique sandbox_restrictions.env))
      else ""
    }\
${if (builtins.hasAttr "allow_nested_sandbox" sandbox_restrictions) && sandbox_restrictions.allow_nested_sandbox then "" else ''--setenv "${consts.SKIP_SANDBOX_ENV_VAR_NAME}" "''$${consts.SKIP_SANDBOX_ENV_VAR_NAME}" \
''}\
--tmpfs /etc/ssh/ssh_config.d \
--seccomp 3 \
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
    (let
      jqFilter = ''{
   name: $name,
   unix_sockets: $sockets,
   network_access: $network,
   real_dev: $real_dev,
   seccomp: {
     inet_blocked: $inet_blocked,
     inet6_blocked: $inet6_blocked,
     unix_blocked: $unix_blocked,
     netlink_blocked: $netlink_blocked,
     packet_blocked: $packet_blocked,
     bluetooth_blocked: $bluetooth_blocked
   },
   share: {
     user: ${if (builtins.hasAttr "share_user" sandbox_restrictions) && sandbox_restrictions.share_user then "true" else "false"},
     uts: ${if (builtins.hasAttr "share_uts" sandbox_restrictions) && sandbox_restrictions.share_uts then "true" else "false"},
     cgroup: ${if (builtins.hasAttr "share_cgroup" sandbox_restrictions) && sandbox_restrictions.share_cgroup then "true" else "false"},
     pid: ${if (builtins.hasAttr "share_pid" sandbox_restrictions) && sandbox_restrictions.share_pid then "true" else "false"},
     ipc: ${if (builtins.hasAttr "share_ipc" sandbox_restrictions) && sandbox_restrictions.share_ipc then "true" else "false"}
   },
   protected_paths: {
${builtins.concatStringsSep ",\n" (builtins.genList (i:
  let
    pp = builtins.elemAt consts.protectedPaths i;
  in ''    "${pp.path}": $prot_${toString i}'') (builtins.length consts.protectedPaths))}
   }
 }'';
      jqFilterFile = pkgs.writeText "${name}-info-filter.jq" jqFilter;
      protectedChecks = builtins.concatStringsSep "" (builtins.genList (i:
        let
          pp = builtins.elemAt consts.protectedPaths i;
          bashPath = if pkgs.lib.hasPrefix "~" pp.path
            then "$HOME" + builtins.substring 1 (-1) pp.path
            else pp.path;
        in ''
protected_${toString i}=false
if [ "${pp.type}" = "dir" ]; then
  if [ -d "${bashPath}" ] && [ -n "$(${pkgs.coreutils}/bin/ls -A "${bashPath}" 2>&1 | ${pkgs.gnugrep}/bin/grep -v "cannot")" ]; then
    protected_${toString i}=true
  fi
else
  if [ -e "${bashPath}" ] && [ ! "${bashPath}" -ef /dev/null ]; then
    protected_${toString i}=true
  fi
fi
'') (builtins.length consts.protectedPaths));
      protectedArgs = builtins.concatStringsSep "" (builtins.genList (i:
        ''  --argjson prot_${toString i} "$protected_${toString i}" \
'') (builtins.length consts.protectedPaths));
      infoScript = pkgs.writeScript "${name}-info-script" ''
#!${pkgs.bash}/bin/bash
# Create a stderr sink since /dev/null may not be writable in sandbox
exec 2>/tmp/info-stderr.log

sockets=$(cd / && ${pkgs.fd}/bin/fd -t s -E /nix -E /proc -E /sys -E /usr -E /lib -E /snap 2>&1 | ${pkgs.gnugrep}/bin/grep -v "^fd:" | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)

network_access=false
iface_count=$(${pkgs.iproute2}/bin/ip -o link show 2>&1 | ${pkgs.gnugrep}/bin/grep -cv ": lo:")
if [ "$iface_count" -gt 0 ]; then
  network_access=true
fi

 real_dev=false
 if [ -e /dev/input ]; then
   real_dev=true
 fi

 # Check if AF_INET sockets are blocked (seccomp returns EACCES=13)
 inet_blocked=false
 if ! ${pkgs.python3}/bin/python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.close()" 2>/dev/null; then
   inet_blocked=true
 fi

 # Check if AF_INET6 sockets are blocked
 inet6_blocked=false
 if ! ${pkgs.python3}/bin/python3 -c "import socket; s=socket.socket(socket.AF_INET6, socket.SOCK_STREAM); s.close()" 2>/dev/null; then
   inet6_blocked=true
 fi

 # Check if AF_UNIX sockets are blocked
 unix_blocked=false
 if ! ${pkgs.python3}/bin/python3 -c "import socket; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.close()" 2>/dev/null; then
   unix_blocked=true
 fi

 # Check if AF_NETLINK sockets are blocked
 netlink_blocked=false
 if ! ${pkgs.python3}/bin/python3 -c "import socket; s=socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM, 0); s.close()" 2>/dev/null; then
   netlink_blocked=true
 fi

 # Check if AF_PACKET sockets are blocked
 packet_blocked=false
 if ! ${pkgs.python3}/bin/python3 -c "import socket; s=socket.socket(socket.AF_PACKET, socket.SOCK_RAW, 0); s.close()" 2>/dev/null; then
   packet_blocked=true
 fi

 # Check if AF_BLUETOOTH sockets are blocked
 bluetooth_blocked=false
 if ! ${pkgs.python3}/bin/python3 -c "import socket; s=socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, 0); s.close()" 2>/dev/null; then
   bluetooth_blocked=true
 fi

${protectedChecks}
 ${pkgs.jq}/bin/jq -n \
   --arg name "${name}" \
   --argjson sockets "$sockets" \
   --argjson network "$network_access" \
   --argjson inet_blocked "$inet_blocked" \
   --argjson inet6_blocked "$inet6_blocked" \
   --argjson unix_blocked "$unix_blocked" \
   --argjson netlink_blocked "$netlink_blocked" \
   --argjson packet_blocked "$packet_blocked" \
   --argjson bluetooth_blocked "$bluetooth_blocked" \
   --argjson real_dev "$real_dev" \
 ${protectedArgs}  -f ${jqFilterFile}
'';
    in pkgs.writeScriptBin "${name}-info" (makeWrapper {
      bin = "${infoScript}";
      bwrapCmd = runInBwrap;
    }))
  ] ++ (
    if generate_unsafe then [(pkgs.writeScriptBin "${name}-unsafe" (makeWrapper {inherit bin; bwrapCmd = "";}))] else []
  );
in
  {
    inherit scripts;
  }
