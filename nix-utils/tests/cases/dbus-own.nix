# Case: the xdg-dbus-proxy `own` rule (the positive side; dbus-proxy-filter covers
# see-hiding). flameshot routes the session bus through the proxy with
# own=["org.flameshot.Flameshot"], so it may claim that name but not any other.
# (No tool declares talk/call/broadcast rules, so those have no real subject and are out
# of scope here.)
{ pkgs }:
{
  testScript = ''
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    req = (
        "busctl --user call org.freedesktop.DBus /org/freedesktop/DBus "
        "org.freedesktop.DBus RequestName su %s 0"
    )

    # Positive: flameshot can own its declared name -> RequestName returns primary-owner (u 1).
    owned = run_user("flameshot-debug -c '" + (req % "org.flameshot.Flameshot") + "' 2>&1")
    assert "u 1" in owned, f"flameshot must be able to own its declared name; got {owned!r}"

    # Negative: a name it did NOT declare is rejected by the proxy's own filter.
    denied = run_user("flameshot-debug -c '" + (req % "org.nixutils.NotAllowed") + "' 2>&1", succeed=False)
    assert "u 1" not in denied, f"the proxy must not let flameshot own an undeclared name; got {denied!r}"
  '';
}
