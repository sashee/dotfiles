# Case: the filtering xdg-dbus-proxy actually filters. flameshot is the one tool
# that routes the session bus through the proxy (sandbox_restrictions.dbus), with a
# maximally restrictive rule (own org.flameshot.Flameshot, no see/talk/call) — so
# inside its sandbox the bus exposes only the driver (org.freedesktop.DBus) and hides
# every other name. isd ro-binds the *raw* bus (no proxy), so it's the unfiltered
# reference. Both are existing -debug shells; busctl --user lists the names the
# connection can see, which the proxy restricts.
{ pkgs }:
{
  testScript = ''
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    # Unfiltered (isd ro-binds the raw bus): sees the driver AND the user manager.
    isd_names = run_user("isd-debug -c 'busctl --user list --no-pager' 2>/dev/null")
    assert "org.freedesktop.DBus" in isd_names, f"raw bus should show the driver: {isd_names!r}"
    assert "org.freedesktop.systemd1" in isd_names, f"raw bus should show systemd1 (sanity): {isd_names!r}"

    # Filtered (flameshot's xdg-dbus-proxy, no see/talk rules): driver only, no systemd1.
    fs_names = run_user("flameshot-debug -c 'busctl --user list --no-pager' 2>/dev/null")
    assert "org.freedesktop.DBus" in fs_names, f"proxy should forward the bus driver: {fs_names!r}"
    assert "org.freedesktop.systemd1" not in fs_names, (
        "the dbus proxy must hide names with no see/talk rule, but "
        f"org.freedesktop.systemd1 was visible through it: {fs_names!r}"
    )
  '';
}
