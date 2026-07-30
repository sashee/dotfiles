# Machinery case: the xdg-dbus-proxy `own` rule (the positive side; dbus-proxy-filter
# covers see-hiding). probe-dbus-own routes the session bus through the proxy with
# own=["org.nixutils.Probe"] and nothing else, so it may claim that name but not any
# other. A synthetic probe rather than a real tool (flameshot was the only one with a
# dbus rule): the proxy is what's under test, and it must be assertable on a machine
# that installs no GUI app at all.
# (No talk/call/broadcast rules are declared anywhere, so those have no subject and are
# out of scope here.)
{ pkgs }:
let
  probeTools = import ../probe-tools { inherit pkgs; };
  # Store path: the probe is not installed on the machine under test.
  shell = probeTools.shell "probe-dbus-own";
in
{
  testScript = ''
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    req = (
        "busctl --user call org.freedesktop.DBus /org/freedesktop/DBus "
        "org.freedesktop.DBus RequestName su %s 0"
    )

    # Positive: the declared name can be owned -> RequestName returns primary-owner (u 1).
    owned = run_user("${shell} -c '" + (req % "org.nixutils.Probe") + "' 2>&1")
    assert "u 1" in owned, f"the proxy must allow owning the declared name; got {owned!r}"

    # Negative: a name it did NOT declare is rejected by the proxy's own filter.
    denied = run_user("${shell} -c '" + (req % "org.nixutils.NotAllowed") + "' 2>&1", succeed=False)
    assert "u 1" not in denied, f"the proxy must not allow owning an undeclared name; got {denied!r}"
  '';
}
