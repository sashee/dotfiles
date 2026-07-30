# Synthetic sandboxed "programs" that exist only for the tests. Each declares ONE
# sandbox profile and carries no real payload, so a machinery case can assert that a
# mechanism works (dbus filtering, seccomp socket families, /dev modes, env scrubbing)
# without borrowing whichever real program happens to have the right config.
#
# That borrowing is exactly what broke: the cases used keepassxc/flameshot/claude as
# profile carriers, and a machine that drops them via lib.nix's `skip` (hosts/rpi5
# skips all three to shrink its closure) failed the machinery tests for a reason that
# has nothing to do with the machinery. It also rots silently — flip keepassxc to
# `dev = false` and the "full /dev" assertion stops testing anything while still
# passing. A probe pins the profile under test in one place.
#
# A probe is built exactly like a real program (launcher.mkLauncher + _wrapper), so it
# gets the same wrapper set and the cases keep their shape:
#   ${bin}/<probe>-shell -c '<cmd>'  # run <cmd> under that profile (no strace: TCG-friendly)
#
# Cases run them by ABSOLUTE STORE PATH and the probes are deliberately NOT installed on
# the machine under test: the machine stays exactly the configuration under test (nothing
# added to its PATH or its closure), and a store path resolves inside every sandbox anyway
# because the host root is ro-bound — the same reason the cases already invoke
# ${pkgs.nodejs}/bin/node and the ./cases/probes.nix payloads that way.
#
# TEST-ONLY. Nothing outside tests/ imports this, so probes cannot reach a real
# machine's environment: ../../lib.nix builds the real env and knows nothing about
# tests/ (the dependency runs tests -> lib.nix, never the reverse).
{ pkgs }:
let
  launcher = import ../../launcher.nix { inherit pkgs; };

  # Enough env to run a store-path payload and reach the session bus. Probes that
  # test scrubbing override this; mkLauncher always adds XDG_RUNTIME_DIR,
  # WAYLAND_DISPLAY and the skip var on top.
  defaultKeepEnv = [ "HOME" "PATH" "TMPDIR" "TERM" "LANG" "XDG_RUNTIME_DIR" "DBUS_SESSION_BUS_ADDRESS" ];

  mkProbe = { name, sandbox_restrictions ? { }, keepEnv ? defaultKeepEnv, setEnv ? { } }:
    let
      bin = launcher.mkLauncher {
        inherit name keepEnv setEnv;
        # Irrelevant in practice: the cases use the -shell/-debug wrappers, which
        # bin.override this target to bash anyway.
        target = "${pkgs.bash}/bin/bash";
      };
    in
    {
      inherit sandbox_restrictions;
      scripts = (import ../../_wrapper/default.nix {
        inherit pkgs name bin sandbox_restrictions;
        # No real binary to launch unsandboxed, so the escape hatch is pointless here.
        generate_unsafe = false;
      }).scripts;
    };

  probes = {
    # Defaults: no `network` -> autoBlock blocks AF_INET/AF_INET6/AF_PACKET and the
    # netns is unshared; no `dev` -> /dev is exactly consts.fakeDevEntries.
    probe-default = mkProbe { name = "probe-default"; };

    # The unrestricted reference: shares the netns, no seccomp filter.
    probe-net = mkProbe {
      name = "probe-net";
      sandbox_restrictions = { network = true; };
    };

    # autoBlock (no network) PLUS an explicit AF_UNIX block: even unix sockets refused.
    probe-unix-blocked = mkProbe {
      name = "probe-unix-blocked";
      sandbox_restrictions = { seccomp.block = { AF_UNIX = true; }; };
    };

    # Shares the netns but seccomp-blocks inet — proves seccomp blocks socket families
    # independently of --unshare-net, and that AF_UNIX still works alongside.
    probe-inet-blocked = mkProbe {
      name = "probe-inet-blocked";
      sandbox_restrictions = {
        network = true;
        seccomp.block = { AF_INET = true; AF_INET6 = true; };
      };
    };

    # The three non-default /dev modes.
    probe-dev-full = mkProbe {
      name = "probe-dev-full";
      sandbox_restrictions = { dev = true; };
    };
    probe-dev-allowlist = mkProbe {
      name = "probe-dev-allowlist";
      sandbox_restrictions = { dev = [ "/dev/kvm" ]; };
    };
    probe-dev-glob = mkProbe {
      name = "probe-dev-glob";
      sandbox_restrictions = { dev = [ "/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm" ]; };
    };

    # Session bus through the filtering xdg-dbus-proxy, with the most restrictive rule
    # there is: may own one name, no see/talk/call. The raw-bus counterpart below is a
    # SEPARATE probe because _wrapper's validateNoConflicts rejects a path that appears
    # in both `fs` and `dbus`.
    probe-dbus-own = mkProbe {
      name = "probe-dbus-own";
      sandbox_restrictions = {
        dbus."$XDG_RUNTIME_DIR/bus" = {
          own = [ "org.nixutils.Probe" ];
          log = true;
        };
      };
    };
    # Unfiltered reference: the real bus socket ro-bound, no proxy in between.
    probe-dbus-raw = mkProbe {
      name = "probe-dbus-raw";
      sandbox_restrictions = { fs."$XDG_RUNTIME_DIR/bus" = { perm = "ro"; }; };
    };

    # Scrubbing launcher: starts from an empty env, re-adds only these, and injects a
    # setEnv var. Anything else on the host must not survive. PROBE_KEEP stands in for a
    # var a real tool deliberately lets through (aws lists AWS_ACCESS_KEY_ID this way),
    # so the test can tell selective re-add apart from "everything passes".
    probe-scrub = mkProbe {
      name = "probe-scrub";
      keepEnv = [ "HOME" "PATH" "TMPDIR" "LANG" "TERM" "PROBE_KEEP" ];
      setEnv = { PROBE_SETENV = "injected"; };
    };
    # keepEnv = null: the host env passes through untouched (the reference case).
    probe-passthru = mkProbe {
      name = "probe-passthru";
      keepEnv = null;
    };
  };
  # All the probe wrappers under one prefix, so a case can name them by store path
  # (`${bin}/probe-dev-full-shell`) without any of them being installed anywhere.
  env = pkgs.buildEnv {
    name = "nix-utils-probe-tools";
    paths = builtins.concatLists (map (p: p.scripts) (builtins.attrValues probes));
  };
in
{
  inherit probes env;
  bin = "${env}/bin";

  # `<probe>-shell` by store path: a bash shell in that probe's real sandbox, without
  # -debug's strace (pathologically slow under aarch64 TCG). Throws at eval time on a
  # typo'd probe name rather than failing in the VM with a confusing 127.
  shell = name:
    if builtins.hasAttr name probes
    then "${env}/bin/${name}-shell"
    else throw "probe-tools: no such probe '${name}' (have: ${builtins.concatStringsSep ", " (builtins.attrNames probes)})";
}
