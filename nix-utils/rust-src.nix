{ pkgs }:
let
  lib = pkgs.lib;
  root = ./.;

  keepPath = cratePath: path: _type:
    let
      prefix = toString root + "/";
      pathString = toString path;
      relPath =
        if pathString == toString root then
          ""
        else
          lib.removePrefix prefix pathString;
    in
      relPath == ""
      || relPath == cratePath
      || lib.hasPrefix (cratePath + "/") relPath
      || lib.hasPrefix (relPath + "/") cratePath;
in
cratePath:
  pkgs.nix-gitignore.gitignoreFilterSource (keepPath cratePath) [] root
