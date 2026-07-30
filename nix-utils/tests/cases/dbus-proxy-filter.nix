# Machinery case: the filtering xdg-dbus-proxy actually filters. Two synthetic probes are
# the two sides of the comparison (see ../probe-tools), so this holds on any machine
# regardless of which real programs it installs:
#   - probe-dbus-own routes the session bus through the proxy with a maximally
#     restrictive rule (own org.nixutils.Probe, no see/talk/call), so inside its sandbox
#     the bus must expose only the driver (org.freedesktop.DBus) and hide every other name.
#   - probe-dbus-raw ro-binds the *raw* bus socket (no proxy), the unfiltered reference.
# busctl --user lists the names the connection can see, which the proxy restricts.
{ pkgs }:
let
  probeTools = import ../probe-tools { inherit pkgs; };
  # Store paths: the probes are not installed on the machine under test.
  raw = probeTools.shell "probe-dbus-raw";
  proxied = probeTools.shell "probe-dbus-own";
in
{
  testScript = ''
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    # Unfiltered (raw bus ro-bound): sees the driver AND the user manager.
    raw_names = run_user("${raw} -c 'busctl --user list --no-pager' 2>/dev/null")
    assert "org.freedesktop.DBus" in raw_names, f"raw bus should show the driver: {raw_names!r}"
    assert "org.freedesktop.systemd1" in raw_names, f"raw bus should show systemd1 (sanity): {raw_names!r}"

    # Filtered (through the proxy, no see/talk rules): driver only, no systemd1.
    proxied_names = run_user("${proxied} -c 'busctl --user list --no-pager' 2>/dev/null")
    assert "org.freedesktop.DBus" in proxied_names, f"proxy should forward the bus driver: {proxied_names!r}"
    assert "org.freedesktop.systemd1" not in proxied_names, (
        "the dbus proxy must hide names with no see/talk rule, but "
        f"org.freedesktop.systemd1 was visible through it: {proxied_names!r}"
    )
  '';
}
