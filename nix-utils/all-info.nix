{pkgs, infoScripts}:
let
  allInfoBin = import ./_wrapper/all-info/default.nix { inherit pkgs; };
  allInfoConfig = pkgs.writeText "all-info-config.json" (builtins.toJSON (map (s: {
    name = s.name;
    path = "${s}/bin/${s.name}";
  }) infoScripts));
in {
  all-info = pkgs.writeScriptBin "all-info" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    ${allInfoBin}/bin/nix-sandbox-all-info --config ${allInfoConfig} --mode table-json | ${pkgs.bubblewrap}/bin/bwrap \
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

    ${allInfoBin}/bin/nix-sandbox-all-info --config ${allInfoConfig} --mode json
  '';
}
