{pkgs, name, sandbox_restrictions, consts, makeWrapper, runInBwrap}:

let
  infoBin = import ./_wrapper/info/default.nix { inherit pkgs; };

  infoConfig = pkgs.writeText "${name}-info-config.json" (builtins.toJSON {
    program_name = name;
    share = {
      user = (builtins.hasAttr "share_user" sandbox_restrictions) && sandbox_restrictions.share_user;
      uts = (builtins.hasAttr "share_uts" sandbox_restrictions) && sandbox_restrictions.share_uts;
      cgroup = (builtins.hasAttr "share_cgroup" sandbox_restrictions) && sandbox_restrictions.share_cgroup;
      pid = (builtins.hasAttr "share_pid" sandbox_restrictions) && sandbox_restrictions.share_pid;
      ipc = (builtins.hasAttr "share_ipc" sandbox_restrictions) && sandbox_restrictions.share_ipc;
    };
    protected_paths = map (pp: {
      path = pp.path;
      type = pp.type;
    }) consts.protectedPaths;
  });

  infoWrapper = pkgs.writeScriptBin "${name}-info" (makeWrapper {
    bin = "${infoBin}/bin/nix-sandbox-info --config ${infoConfig}";
    bwrapCmd = runInBwrap;
  });
in
  infoWrapper
