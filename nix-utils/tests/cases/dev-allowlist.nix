# Case: the /dev whitelisting behavior through the REAL tool wrappers (the runtime
# masking the runner layers on top of bwrap). dev-baseline.nix guards the
# consts.fakeDevEntries constant against raw `bwrap --dev` drift; this exercises the
# three modes end to end:
#   - allowlist  (opencode `dev=["/dev/kvm"]`): real /dev bound, then every entry that is
#       neither a baseline node nor an allowlist match is masked -> files become
#       `--ro-bind /dev/null <path>`. So a sensitive device (mem/kmsg) and a real block
#       device (vda) end up reporting /dev/null's device numbers (block also flips to
#       char), while a baseline device (zero) stays the real one.
#   - fake       (sqlite3, no `dev`): /dev is exactly the baseline; no real devices.
#   - full       (keepassxc `dev=true`): real /dev, unmasked.
#   - glob       (zsh `dev=["/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm"]`): the globs must
#       not over-match into allow-all -> non-matching sensitive/block devices stay masked.
#
# Probed with a RAW (non-wrapped) coreutils helper, NOT the wrapped `node`: zsh sets
# __NIX_UTILS_SKIP_SANDBOX=false, so a wrapped tool launched inside it would re-sandbox
# with its OWN dev config (fake /dev) and we'd measure the wrong sandbox. A raw store-
# path script just runs in the tool's sandbox. Masking is detected via stat's st_rdev
# (major|minor): a `/dev/null`-bound device reports null's numbers; a real device differs.
{ pkgs }:
let
  consts = import ../../consts.nix;
  probes = import ./probes.nix { inherit pkgs; };
  coreutils = pkgs.coreutils;
  devs = "/dev/null /dev/zero /dev/mem /dev/kmsg /dev/vda /dev/ttyS0 /dev/kvm";
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

    def dev_info(tool):
        raw = run_user("%s-debug -c '${devProbe} ${devs}'" % tool)
        info = {}
        for line in raw.strip().splitlines():
            f = line.split("|")
            info[f[0]] = {"exists": False} if f[1] == "ABSENT" else {
                "exists": True, "type": f[1], "dev": (f[2], f[3])
            }
        return info

    # 1) Allowlist tool (opencode, dev=["/dev/kvm"]): mask everything but baseline+allowlist.
    o = dev_info("opencode")
    nul = o["/dev/null"]
    assert nul["exists"] and nul["type"].startswith("character"), f"/dev/null baseline broken under opencode: {nul}"
    for d in ["/dev/mem", "/dev/kmsg"]:
        assert o[d]["exists"] and o[d]["dev"] == nul["dev"], (
            f"opencode (dev=[/dev/kvm]) must mask the sensitive device {d} to /dev/null; got {o[d]}"
        )
    assert o["/dev/vda"]["exists"] and o["/dev/vda"]["type"].startswith("character") and o["/dev/vda"]["dev"] == nul["dev"], (
        f"opencode must mask the real block device /dev/vda to /dev/null; got {o['/dev/vda']}"
    )
    assert o["/dev/zero"]["exists"] and o["/dev/zero"]["dev"] != nul["dev"], (
        f"the baseline /dev/zero must stay the real device under opencode; got {o['/dev/zero']}"
    )
    # The allowlisted device passes through unmasked — only assertable if the VM has it.
    if o["/dev/kvm"]["exists"]:
        assert o["/dev/kvm"]["dev"] != nul["dev"], (
            f"allowlisted /dev/kvm must pass through unmasked, not be /dev/null; got {o['/dev/kvm']}"
        )

    # 2) Fake /dev (sqlite3, no `dev`): exactly the baseline, no real devices.
    entries = set(run_user("sqlite3-debug -c '${coreutils}/bin/ls -1A /dev'").split())
    assert entries == fake, (
        f"a no-dev tool's /dev must be exactly the baseline: "
        f"missing={sorted(fake - entries)}, extra={sorted(entries - fake)}"
    )
    s = dev_info("sqlite3")
    assert not s["/dev/mem"]["exists"], f"fake /dev must not expose /dev/mem; got {s['/dev/mem']}"
    assert not s["/dev/kvm"]["exists"], f"fake /dev must not expose /dev/kvm; got {s['/dev/kvm']}"
    assert s["/dev/null"]["exists"] and s["/dev/null"]["type"].startswith("character"), f"fake /dev/null broken: {s['/dev/null']}"

    # 3) Full /dev (keepassxc, dev=true): the REAL device, unmasked.
    k = dev_info("keepassxc")
    knul = k["/dev/null"]
    assert k["/dev/mem"]["exists"] and k["/dev/mem"]["dev"] != knul["dev"], (
        f"keepassxc (dev=true) must expose the real, unmasked /dev/mem; got {k['/dev/mem']}"
    )

    # 4) Glob allowlist (zsh, dev=["/dev/ttyUSB*" "/dev/ttyACM*" "/dev/kvm"]): the globs
    # must not over-match into allow-all — non-matching sensitive/block devices stay masked.
    z = dev_info("zsh")
    znul = z["/dev/null"]
    for d in ["/dev/mem", "/dev/kmsg"]:
        assert z[d]["exists"] and z[d]["dev"] == znul["dev"], (
            f"zsh's glob allowlist must still mask the sensitive device {d} (globs must not over-match); got {z[d]}"
        )
    assert z["/dev/vda"]["exists"] and z["/dev/vda"]["dev"] == znul["dev"], (
        f"zsh must mask the real block device /dev/vda; got {z['/dev/vda']}"
    )
    assert z["/dev/zero"]["exists"] and z["/dev/zero"]["dev"] != znul["dev"], (
        f"the baseline /dev/zero must stay the real device under zsh; got {z['/dev/zero']}"
    )
    # Precise glob non-match: /dev/ttyUSB* must not match the console /dev/ttyS0 (only
    # checkable when that flaky console node is actually present at launch).
    if z["/dev/ttyS0"]["exists"]:
        assert z["/dev/ttyS0"]["dev"] == znul["dev"], (
            f"/dev/ttyUSB* must not match /dev/ttyS0 -> it must be masked; got {z['/dev/ttyS0']}"
        )
  '';
}
