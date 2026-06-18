# Case: a tool that opts into real_machine_id=true (isd needs the host machine-id
# for journalctl) sees the HOST /etc/machine-id, not a faked one — the opt-in
# counterpart to the machine-id case (which checks the faked default). isd-debug
# gives a bash inside isd's sandbox, so no code is needed, just the test.
{ pkgs }:
{
  testScript = ''
    host = machine.succeed("cat /etc/machine-id").strip()
    isd_mid = run_user("isd-debug -c 'cat /etc/machine-id'").strip()
    assert isd_mid == host, (
        f"isd (real_machine_id=true) should see the host machine-id: "
        f"got {isd_mid!r} vs host {host!r}"
    )
  '';
}
