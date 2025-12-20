{pkgs, infoScripts}:
{
  all-info = pkgs.writeScriptBin "all-info" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Collect all JSON outputs
    outputs=()
    ${builtins.concatStringsSep "\n" (map (s: ''
    output=$(${s}/bin/${s.name})
    if [ -z "$output" ]; then
      echo "Error: empty output from ${s.name}" >&2
      exit 1
    fi
    outputs+=("$output")
    '') infoScripts)}

    # Restructure JSON with nested objects for visidata
    printf '%s\n' "''${outputs[@]}" | ${pkgs.jq}/bin/jq -s '[.[] | {
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
  '';

  all-info-json = pkgs.writeScriptBin "all-info-json" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Collect all JSON outputs
    outputs=()
    ${builtins.concatStringsSep "\n" (map (s: ''
    output=$(${s}/bin/${s.name})
    if [ -z "$output" ]; then
      echo "Error: empty output from ${s.name}" >&2
      exit 1
    fi
    outputs+=("$output")
    '') infoScripts)}

    # Output as pretty-printed JSON object keyed by name
    printf '%s\n' "''${outputs[@]}" | ${pkgs.jq}/bin/jq -s '[.[] | {(.name): .}] | add' --indent 2
  '';
}