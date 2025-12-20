{pkgs, infoScripts}:
pkgs.writeScriptBin "all-info" ''
  #!${pkgs.bash}/bin/bash

  # Collect all JSON outputs
  json_outputs=""
  ${builtins.concatStringsSep "\n" (map (s: ''
  output=$(${pkgs.coreutils}/bin/timeout 10s ${s}/bin/${s.name} 2>/dev/null)
  if [ -n "$output" ]; then
    if [ -n "$json_outputs" ]; then
      json_outputs="$json_outputs,$output"
    else
      json_outputs="$output"
    fi
  fi
  '') infoScripts)}

  # Create array and restructure JSON with nested objects for visidata
  echo "[$json_outputs]" | ${pkgs.jq}/bin/jq '[.[] | {
    name,
    network_access,
    real_dev,
    seccomp_bitmap: (.seccomp.inet_blocked | if . then " " else "X" end) + (.seccomp.inet6_blocked | if . then " " else "X" end) + (.seccomp.unix_blocked | if . then " " else "X" end) + (.seccomp.netlink_blocked | if . then " " else "X" end) + (.seccomp.packet_blocked | if . then " " else "X" end) + (.seccomp.bluetooth_blocked | if . then " " else "X" end),
    seccomp,
    share_bitmap: (.share.user | if . then "X" else " " end) + (.share.uts | if . then "X" else " " end) + (.share.cgroup | if . then "X" else " " end) + (.share.pid | if . then "X" else " " end) + (.share.ipc | if . then "X" else " " end),
    share,
    protected_paths_bitmap: (.protected_paths | to_entries | sort_by(.key) | map(if .value then "X" else " " end) | join("")),
    protected_paths: (.protected_paths | to_entries | sort_by(.key) | from_entries)
  }]' | ${pkgs.bubblewrap}/bin/bwrap \
    --unshare-all \
    --ro-bind / / \
    --dev /dev \
    --proc /proc \
    --die-with-parent \
    ${pkgs.visidata}/bin/vd -f json
''