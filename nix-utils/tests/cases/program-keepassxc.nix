# Per-program case: keepassxc's own intent, asserted only if this machine installs it
# (headless machines drop the GUI apps via lib.nix's `skip`). The sandbox mechanisms this
# relies on are covered independently by the machinery cases (seccomp.nix, dev-allowlist.nix)
# under the synthetic probes, so skipping here loses only keepassxc-specific coverage.
#
# What keepassxc must hold, and why it is not derivable from its config (asserting that the
# config says what the config says would prove nothing):
#   - A password manager must not be able to reach the internet. It runs with network=true
#     (it needs the netns for udev/netlink), so the netns alone does NOT protect it — the
#     seccomp inet block is the only thing standing in the way, and that is worth an
#     explicit end-to-end assertion.
#   - AF_UNIX must still work: it talks to the ssh-agent and the session bus.
#   - It gets the real /dev (dev=true) for hardware-key access, unmasked.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  coreutils = pkgs.coreutils;
  # node by store path: keepassxc's keepEnv has no PATH entry pointing at node, and a
  # store path resolves inside the sandbox (host root is ro-bound) without the machine
  # needing node in its system profile.
  sock = fam: "keepassxc-shell -c '${pkgs.nodejs}/bin/node ${probes.socketFamily} ${fam}'";
in
{
  testScript = ''
    if not present("keepassxc"):
        skip_absent("keepassxc")
    else:
        # 1) No internet, despite sharing the netns: socket(AF_INET) is refused outright.
        for fam in ["udp4", "udp6"]:
            out = run_user("${sock "%s"}" % fam)
            assert "ERR:EACCES" in out, (
                f"keepassxc must not be able to open an inet ({fam}) socket — it holds "
                f"secrets and has no business on the network; got {out!r}"
            )

        # 2) but AF_UNIX still works (ssh-agent, session bus).
        assert "OK" == run_user("${sock "unix"}").strip(), "keepassxc must still be able to use AF_UNIX"

        # 3) Real, unmasked /dev (hardware keys): /dev/mem is the real node, not /dev/null.
        raw = run_user("keepassxc-shell -c '${coreutils}/bin/stat -c %t:%T /dev/mem /dev/null'")
        mem, nul = raw.split()
        assert mem != nul, f"keepassxc (dev=true) must see the real unmasked /dev/mem, not a /dev/null mask; got {mem} vs {nul}"
  '';
}
