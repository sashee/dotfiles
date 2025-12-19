{pkgs, name, sandbox_restrictions, consts, makeWrapper, runInBwrap}:

let
  # JQ filter for JSON output
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

  # Generate protected path checks
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
''
  ) (builtins.length consts.protectedPaths));

  protectedArgs = builtins.concatStringsSep "" (builtins.genList (i:
    ''  --argjson prot_${toString i} "$protected_${toString i}" \
''
  ) (builtins.length consts.protectedPaths));

  # Create the info script
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

  # Create the info script wrapper
  infoWrapper = pkgs.writeScriptBin "${name}-info" (makeWrapper {
    bin = "${infoScript}";
    bwrapCmd = runInBwrap;
  });
in
  infoWrapper