# Case: System V IPC namespace isolation (--unshare-ipc). Default tools get a fresh IPC
# namespace, so SysV shared-memory segments / message queues created on the host are
# invisible inside the sandbox — closing a shared-memory side channel between host and
# sandboxed tool.
{ pkgs }:
let
  util = pkgs.util-linux;
in
{
  testScript = ''
    # Create a SysV shared-memory segment on the host (the VM's init IPC namespace).
    mk = machine.succeed("${util}/bin/ipcmk -M 4096")
    shmid = mk.strip().split(":")[-1].strip()
    assert shmid.isdigit(), f"could not parse shmid from ipcmk output: {mk!r}"
    try:
        assert shmid in machine.succeed("${util}/bin/ipcs -m"), "sanity: host ipcs should list the new segment"
        # A default tool is launched with --unshare-ipc -> a fresh IPC namespace, so the
        # host segment must not be visible.
        inside = run_user("sqlite3-debug -c '${util}/bin/ipcs -m'")
        assert shmid not in inside, (
            f"--unshare-ipc must hide host SysV shm {shmid} from the sandbox; got:\n{inside}"
        )
    finally:
        machine.succeed("${util}/bin/ipcrm -m " + shmid)
  '';
}
