# Per-program case: flameshot's own intent, asserted only if this machine installs it
# (headless machines drop the GUI apps via lib.nix's `skip`). The dbus-proxy and seccomp
# machinery it relies on is covered independently by dbus-own.nix / dbus-proxy-filter.nix /
# seccomp.nix under the synthetic probes, so skipping here loses only flameshot's own
# coverage.
#
# What flameshot must hold:
#   - It is the one tool that routes the session bus through the filtering proxy (it needs
#     the bus to register its own name), so its connection must see the driver and NOTHING
#     else — in particular not the user's systemd manager, which would be a way out.
#   - It may claim its declared name and no other.
#   - A screenshot tool has no business on the network.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  # node by store path: works regardless of the machine's system profile and of what
  # flameshot's keepEnv leaves on PATH.
  sock = fam: "flameshot-shell -c '${pkgs.nodejs}/bin/node ${probes.socketFamily} ${fam}'";
in
{
  testScript = ''
    if not present("flameshot"):
        skip_absent("flameshot")
    else:
        machine.wait_until_succeeds("test -S /run/user/1000/bus")

        # 1) Its bus connection is filtered: the driver is reachable, the user manager is not.
        seen = run_user("flameshot-shell -c 'busctl --user list --no-pager' 2>/dev/null")
        assert "org.freedesktop.DBus" in seen, f"flameshot needs the bus driver: {seen!r}"
        assert "org.freedesktop.systemd1" not in seen, (
            "flameshot's dbus proxy must hide the user systemd manager (it declares no see/talk "
            f"rule for it); got {seen!r}"
        )

        # 2) It may own the name it declares, and only that one.
        req = (
            "busctl --user call org.freedesktop.DBus /org/freedesktop/DBus "
            "org.freedesktop.DBus RequestName su %s 0"
        )
        owned = run_user("flameshot-shell -c '" + (req % "org.flameshot.Flameshot") + "' 2>&1")
        assert "u 1" in owned, f"flameshot must be able to own org.flameshot.Flameshot; got {owned!r}"
        denied = run_user("flameshot-shell -c '" + (req % "org.nixutils.NotAllowed") + "' 2>&1", succeed=False)
        assert "u 1" not in denied, f"flameshot must not be able to own an undeclared name; got {denied!r}"

        # 3) No network.
        for fam in ["udp4", "udp6"]:
            out = run_user("${sock "%s"}" % fam)
            assert "ERR:EACCES" in out, f"flameshot must not be able to open an inet ({fam}) socket; got {out!r}"
  '';
}
