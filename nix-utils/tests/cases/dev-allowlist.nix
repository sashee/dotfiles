# Machinery case: the /dev whitelisting behaviour through the wrapper stack (the runtime
# masking the runner layers on top of bwrap). dev-baseline.nix guards the
# consts.fakeDevEntries constant against raw `bwrap --dev` drift; this exercises the four
# modes end to end, each carried by a synthetic probe (see ../probe-tools) so the modes
# are pinned by the test itself instead of by whichever real tool is configured that way:
#   - allowlist (probe-dev-allowlist, `dev=["/dev/kvm"]`): real /dev bound, then every
#       entry that is neither a baseline node nor an allowlist match is masked -> files
#       become `--ro-bind /dev/null <path>`. So a sensitive device (mem/kmsg) and a real
#       block device (vda) end up reporting /dev/null's device numbers (block also flips
#       to char), while a baseline device (zero) stays the real one.
#   - fake      (probe-default, no `dev`): /dev is exactly the baseline; no real devices.
#   - full      (probe-dev-full, `dev=true`): real /dev, unmasked.
#   - glob      (probe-dev-glob, `dev=["/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm"]`): the
#       globs must not over-match into allow-all -> non-matching sensitive/block devices
#       stay masked.
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
  }) [ "probe-dev-allowlist" "probe-default" "probe-dev-full" "probe-dev-glob" ]));
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
in
{
  testScript = ''
    fake = set(${builtins.toJSON consts.fakeDevEntries})
    SHELL = ${shells}

    def dev_info(tool):
        raw = run_user("%s -c '${devProbe} ${devs}'" % SHELL[tool])
        info = {}
        for line in raw.strip().splitlines():
            f = line.split("|")
            info[f[0]] = {"exists": False} if f[1] == "ABSENT" else {
                "exists": True, "type": f[1], "dev": (f[2], f[3])
            }
        return info

    # 1) Allowlist profile (dev=["/dev/kvm"]): mask everything but baseline+allowlist.
    o = dev_info("probe-dev-allowlist")
    nul = o["/dev/null"]
    assert nul["exists"] and nul["type"].startswith("character"), f"/dev/null baseline broken under the allowlist profile: {nul}"
    for d in ["/dev/mem", "/dev/kmsg"]:
        assert o[d]["exists"] and o[d]["dev"] == nul["dev"], (
            f"dev=[/dev/kvm] must mask the sensitive device {d} to /dev/null; got {o[d]}"
        )
    assert o["/dev/vda"]["exists"] and o["/dev/vda"]["type"].startswith("character") and o["/dev/vda"]["dev"] == nul["dev"], (
        f"the allowlist profile must mask the real block device /dev/vda to /dev/null; got {o['/dev/vda']}"
    )
    assert o["/dev/zero"]["exists"] and o["/dev/zero"]["dev"] != nul["dev"], (
        f"the baseline /dev/zero must stay the real device under the allowlist profile; got {o['/dev/zero']}"
    )
    # The allowlisted device passes through unmasked — only assertable if the VM has it.
    if o["/dev/kvm"]["exists"]:
        assert o["/dev/kvm"]["dev"] != nul["dev"], (
            f"allowlisted /dev/kvm must pass through unmasked, not be /dev/null; got {o['/dev/kvm']}"
        )

    # 2) Fake /dev (no `dev`): exactly the baseline, no real devices.
    entries = set(run_user("%s -c '${coreutils}/bin/ls -1A /dev'" % SHELL["probe-default"]).split())
    assert entries == fake, (
        f"a no-dev profile's /dev must be exactly the baseline: "
        f"missing={sorted(fake - entries)}, extra={sorted(entries - fake)}"
    )
    s = dev_info("probe-default")
    assert not s["/dev/mem"]["exists"], f"fake /dev must not expose /dev/mem; got {s['/dev/mem']}"
    assert not s["/dev/kvm"]["exists"], f"fake /dev must not expose /dev/kvm; got {s['/dev/kvm']}"
    assert s["/dev/null"]["exists"] and s["/dev/null"]["type"].startswith("character"), f"fake /dev/null broken: {s['/dev/null']}"

    # 3) Full /dev (dev=true): the REAL device, unmasked.
    k = dev_info("probe-dev-full")
    knul = k["/dev/null"]
    assert k["/dev/mem"]["exists"] and k["/dev/mem"]["dev"] != knul["dev"], (
        f"dev=true must expose the real, unmasked /dev/mem; got {k['/dev/mem']}"
    )

    # 4) Glob allowlist (dev=["/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm"]): the globs must
    # not over-match into allow-all — non-matching sensitive/block devices stay masked.
    z = dev_info("probe-dev-glob")
    znul = z["/dev/null"]
    for d in ["/dev/mem", "/dev/kmsg"]:
        assert z[d]["exists"] and z[d]["dev"] == znul["dev"], (
            f"a glob allowlist must still mask the sensitive device {d} (globs must not over-match); got {z[d]}"
        )
    assert z["/dev/vda"]["exists"] and z["/dev/vda"]["dev"] == znul["dev"], (
        f"the glob profile must mask the real block device /dev/vda; got {z['/dev/vda']}"
    )
    assert z["/dev/zero"]["exists"] and z["/dev/zero"]["dev"] != znul["dev"], (
        f"the baseline /dev/zero must stay the real device under the glob profile; got {z['/dev/zero']}"
    )
    # Precise glob non-match: /dev/ttyUSB* must not match the console /dev/ttyS0 (only
    # checkable when that flaky console node is actually present at launch).
    if z["/dev/ttyS0"]["exists"]:
        assert z["/dev/ttyS0"]["dev"] == znul["dev"], (
            f"/dev/ttyUSB* must not match /dev/ttyS0 -> it must be masked; got {z['/dev/ttyS0']}"
        )
  '';
}
