# Machinery case: the /dev modes through the wrapper stack. dev-baseline.nix guards the
# consts.fakeDevEntries constant against raw `bwrap --dev` drift; this exercises the modes
# end to end, each carried by a synthetic probe (see ../probe-tools) so the modes are
# pinned by the test itself instead of by whichever real tool is configured that way:
#   - allowlist (probe-dev-allowlist, `dev=["/dev/kvm"]`): bwrap's private /dev plus the
#       matching host devices bound in at launch. Nothing else from the host exists, and
#       pts/shm are bwrap's own (not the host's terminals / shared memory).
#   - glob      (probe-dev-glob, `dev=["/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm"]`): the
#       globs must not over-match -> non-matching sensitive/block devices stay absent.
#   - live      (probe-dev-live, `dev={live=[same globs];}`, zellij/tmux): the live host
#       /dev, every entry that is neither a baseline node nor a match masked at launch
#       -> files become `--ro-bind /dev/null <path>`, so a sensitive device (mem/kmsg)
#       and a real block device (vda) report /dev/null's device numbers (block flips to
#       char), while a baseline device (zero) stays real. pts/shm are the host's.
#   - fake      (probe-default, no `dev`): /dev is exactly the baseline; no real devices.
#   - full      (probe-dev-full, `dev=true`): real /dev, unmasked.
# Plus the hotplug trade-off between live and allowlist, with a device "plugged in"
# (mknod as root) while sandboxes are running.
#
# Probed with a RAW (non-wrapped) coreutils helper rather than a wrapped tool, so what we
# measure is the profile's own /dev and not some nested tool's. Masking is detected via
# stat's st_rdev (major|minor): a `/dev/null`-bound device reports null's numbers; a real
# device differs. -shell rather than -debug: same sandbox without strace, which is
# pathologically slow under aarch64 TCG.
{ pkgs }:
let
  consts = import ../../consts.nix;
  probeTools = import ../probe-tools { inherit pkgs; };
  coreutils = pkgs.coreutils;
  devs = "/dev/null /dev/zero /dev/mem /dev/kmsg /dev/vda /dev/ttyS0 /dev/kvm";
  # profile name -> its -shell store path, handed to the test script as a dict so the
  # assertions can keep naming profiles rather than paths.
  shells = builtins.toJSON (builtins.listToAttrs (map (n: {
    name = n;
    value = probeTools.shell n;
  }) [ "probe-dev-allowlist" "probe-default" "probe-dev-full" "probe-dev-glob" "probe-dev-live" ]));
  # Per path, print "<path>|<%F type>|<%t major>|<%T minor>" or "<path>|ABSENT".
  devProbe = pkgs.writeShellScript "dev-probe.sh" ''
    for p in "$@"; do
      if [ -e "$p" ]; then
        printf '%s|%s\n' "$p" "$(${coreutils}/bin/stat -c '%F|%t|%T' "$p")"
      else
        printf '%s|ABSENT\n' "$p"
      fi
    done
  '';
  # Device-number of the /dev/pts filesystem, and whether a host-side /dev/shm marker
  # is visible: tells a private pts/shm (bwrap's) from the host's.
  ptsShmProbe = pkgs.writeShellScript "pts-shm-probe.sh" ''
    ${coreutils}/bin/stat -c 'PTS=%d' /dev/pts
    if [ -e /dev/shm/nixutils-shm-probe ]; then echo SHM=host; else echo SHM=private; fi
  '';
  # Runs inside a sandbox: signal it is up, wait until the device is "plugged in", then
  # record what THIS sandbox sees and, given a -shell as $2, what a FRESH nested sandbox
  # started now sees (a new zellij pane). The skip var is forced off for the nested one:
  # inside a sandbox it is "true", which would make the nested wrapper skip bwrap.
  hotplugWaiter = pkgs.writeShellScript "hotplug-waiter.sh" ''
    dir="$HOME/nixutils-hotplug"
    : > "$dir/$1.ready"
    while [ ! -e "$dir/go" ]; do ${coreutils}/bin/sleep 0.2; done
    ${devProbe} /dev/ttyUSB9 > "$dir/$1.out"
    if [ -n "''${2:-}" ]; then
      __NIX_UTILS_SKIP_SANDBOX=false "$2" -c '${devProbe} /dev/ttyUSB9' > "$dir/$1.nested"
    fi
    : > "$dir/$1.done"
  '';
in
{
  testScript = ''
    fake = set(${builtins.toJSON consts.fakeDevEntries})
    SHELL = ${shells}

    def parse_dev(raw):
        info = {}
        for line in raw.strip().splitlines():
            f = line.split("|")
            info[f[0]] = {"exists": False} if f[1] == "ABSENT" else {
                "exists": True, "type": f[1], "dev": (f[2], f[3])
            }
        return info

    def dev_info(tool):
        return parse_dev(run_user("%s -c '${devProbe} ${devs}'" % SHELL[tool]))

    host = parse_dev(machine.succeed("${devProbe} ${devs}"))

    # 1) Allowlist (dev=["/dev/kvm"]): private /dev + the allowed device, nothing else.
    o = dev_info("probe-dev-allowlist")
    assert o["/dev/null"]["exists"] and o["/dev/null"]["type"].startswith("character"), f"/dev/null broken under the allowlist profile: {o['/dev/null']}"
    assert o["/dev/zero"]["exists"] and o["/dev/zero"]["dev"] != o["/dev/null"]["dev"], f"baseline /dev/zero must be the real device; got {o['/dev/zero']}"
    for d in ["/dev/mem", "/dev/kmsg", "/dev/vda", "/dev/ttyS0"]:
        assert not o[d]["exists"], f"dev=[/dev/kvm] must not expose {d} at all (private /dev); got {o[d]}"
    # The allowlisted device is the host's real one — only assertable if the VM has it.
    if host["/dev/kvm"]["exists"]:
        assert o["/dev/kvm"]["exists"] and o["/dev/kvm"]["dev"] == host["/dev/kvm"]["dev"], (
            f"allowlisted /dev/kvm must be bound in as the real device {host['/dev/kvm']}; got {o['/dev/kvm']}"
        )

    # 2) Glob allowlist: the globs must not over-match into allow-all.
    z = dev_info("probe-dev-glob")
    for d in ["/dev/mem", "/dev/kmsg", "/dev/vda", "/dev/ttyS0"]:
        assert not z[d]["exists"], f"a glob allowlist must not expose {d} (globs must not over-match); got {z[d]}"
    assert z["/dev/zero"]["exists"] and z["/dev/zero"]["dev"] != z["/dev/null"]["dev"], f"baseline /dev/zero broken under the glob profile; got {z['/dev/zero']}"

    # 3) Live (zellij/tmux): host /dev with everything not allowed masked to /dev/null.
    v = dev_info("probe-dev-live")
    vnul = v["/dev/null"]
    for d in ["/dev/mem", "/dev/kmsg"]:
        assert v[d]["exists"] and v[d]["dev"] == vnul["dev"], (
            f"live mode must mask the sensitive device {d} to /dev/null; got {v[d]}"
        )
    assert v["/dev/vda"]["exists"] and v["/dev/vda"]["type"].startswith("character") and v["/dev/vda"]["dev"] == vnul["dev"], (
        f"live mode must mask the real block device /dev/vda to /dev/null; got {v['/dev/vda']}"
    )
    assert v["/dev/zero"]["exists"] and v["/dev/zero"]["dev"] != vnul["dev"], (
        f"the baseline /dev/zero must stay the real device in live mode; got {v['/dev/zero']}"
    )
    # /dev/ttyUSB* must not match the console /dev/ttyS0 (only checkable when that flaky
    # console node is actually present at launch).
    if v["/dev/ttyS0"]["exists"]:
        assert v["/dev/ttyS0"]["dev"] == vnul["dev"], (
            f"/dev/ttyUSB* must not match /dev/ttyS0 -> it must be masked; got {v['/dev/ttyS0']}"
        )
    if host["/dev/kvm"]["exists"]:
        assert v["/dev/kvm"]["exists"] and v["/dev/kvm"]["dev"] == host["/dev/kvm"]["dev"], (
            f"allowlisted /dev/kvm must pass through unmasked in live mode; got {v['/dev/kvm']}"
        )

    # 4) Fake /dev (no `dev`): exactly the baseline, no real devices.
    entries = set(run_user("%s -c '${coreutils}/bin/ls -1A /dev'" % SHELL["probe-default"]).split())
    assert entries == fake, (
        f"a no-dev profile's /dev must be exactly the baseline: "
        f"missing={sorted(fake - entries)}, extra={sorted(entries - fake)}"
    )
    s = dev_info("probe-default")
    assert not s["/dev/mem"]["exists"], f"fake /dev must not expose /dev/mem; got {s['/dev/mem']}"
    assert not s["/dev/kvm"]["exists"], f"fake /dev must not expose /dev/kvm; got {s['/dev/kvm']}"
    assert s["/dev/null"]["exists"] and s["/dev/null"]["type"].startswith("character"), f"fake /dev/null broken: {s['/dev/null']}"

    # 5) Full /dev (dev=true): the REAL device, unmasked.
    k = dev_info("probe-dev-full")
    assert k["/dev/mem"]["exists"] and k["/dev/mem"]["dev"] != k["/dev/null"]["dev"], (
        f"dev=true must expose the real, unmasked /dev/mem; got {k['/dev/mem']}"
    )

    # 6) Terminals and shared memory: allowlist modes get bwrap's private pts/shm, so a
    # sandboxed program can't open the user's other terminals or the host's /dev/shm.
    # live/full share the host's — the price live pays for hotplug.
    host_pts = machine.succeed("${coreutils}/bin/stat -c 'PTS=%d' /dev/pts").strip()
    run_user("touch /dev/shm/nixutils-shm-probe")
    try:
        for tool, shared in [
            ("probe-dev-allowlist", False),
            ("probe-dev-glob", False),
            ("probe-default", False),
            ("probe-dev-live", True),
            ("probe-dev-full", True),
        ]:
            out = run_user("%s -c '${ptsShmProbe}'" % SHELL[tool])
            pts_shared = host_pts in out.split()
            shm_shared = "SHM=host" in out
            assert pts_shared == shared and shm_shared == shared, (
                f"{tool}: expected {'host' if shared else 'private'} /dev/pts and /dev/shm; "
                f"host {host_pts}, sandbox {out.split()}"
            )
    finally:
        run_user("rm -f /dev/shm/nixutils-shm-probe")

    # 7) Hotplug: a device appearing while sandboxes run (mknod as root, USB-serial
    # 188:9 = st_rdev bc|9). Started BEFORE it appears:
    #   - live sees it, unmasked (zellij/tmux keep up with plugged-in devices);
    #   - allowlist does not (fixed at launch: fail closed).
    # A FRESH allowlist sandbox started inside the live one AFTER it appeared binds it in
    # (a new zellij pane picks up a newly plugged board).
    home = run_user("echo $HOME").strip()
    hp = home + "/nixutils-hotplug"
    run_user("rm -rf ~/nixutils-hotplug && mkdir ~/nixutils-hotplug")
    run_user("(%s -c '${hotplugWaiter} live %s' >/dev/null 2>&1 &)" % (SHELL["probe-dev-live"], SHELL["probe-dev-glob"]))
    run_user("(%s -c '${hotplugWaiter} glob' >/dev/null 2>&1 &)" % SHELL["probe-dev-glob"])
    try:
        machine.wait_until_succeeds(f"test -e {hp}/live.ready && test -e {hp}/glob.ready")
        machine.succeed("mknod -m 0660 /dev/ttyUSB9 c 188 9")
        run_user("touch ~/nixutils-hotplug/go")
        machine.wait_until_succeeds(f"test -e {hp}/live.done && test -e {hp}/glob.done")
        late_live = parse_dev(machine.succeed(f"cat {hp}/live.out"))["/dev/ttyUSB9"]
        late_glob = parse_dev(machine.succeed(f"cat {hp}/glob.out"))["/dev/ttyUSB9"]
        fresh = parse_dev(machine.succeed(f"cat {hp}/live.nested"))["/dev/ttyUSB9"]
    finally:
        machine.succeed("rm -f /dev/ttyUSB9")
        run_user("rm -rf ~/nixutils-hotplug")
    assert late_live["exists"] and late_live["dev"] == ("bc", "9"), (
        f"live mode must see a device plugged in after launch, unmasked; got {late_live}"
    )
    assert not late_glob["exists"], (
        f"allowlist mode must not see a device plugged in after launch; got {late_glob}"
    )
    assert fresh["exists"] and fresh["dev"] == ("bc", "9"), (
        f"a fresh allowlist sandbox started inside live mode must bind the new device; got {fresh}"
    )
  '';
}
