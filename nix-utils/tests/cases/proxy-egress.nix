# Case: a tool with network="proxy" (node-proxy) reaches the internet ONLY through
# the HTTP egress proxy — an isolated netns whose sole egress is the bind-mounted
# UDS to the host-side proxy. Verified three ways: (1) AF_INET is usable (unlike
# network=false), (2) an upstream server is reachable *through the proxy*, and
# (3) a DIRECT connection from the isolated netns cannot reach that same server
# (fail-closed — no route except the proxy).
#
# The upstream server is run by `node` (network=true), which shares the VM netns
# — the same netns the proxy's tinyproxy runs in — so the proxy can reach it,
# while node-proxy (own empty netns) cannot reach it directly.
{ pkgs }:
let
  probes = import ./probes.nix { inherit pkgs; };
  port = "8124";  # upstream server port; distinct from the proxy loopback port (8118)
in
{
  testScript = ''
    # proxy mode allows AF_INET (loopback for the relay); network=false does not.
    run_user("node-proxy ${probes.bindUdp}")                 # binds OK (AF_INET allowed)
    run_user("node-nonet ${probes.bindUdp}", succeed=False)  # contrast: seccomp EACCES

    # Upstream HTTP server in the VM netns (run by `node`, which shares it).
    run_user("(node ${probes.httpServer} 127.0.0.1 ${port} >/tmp/nsr-httpd.log 2>&1 & echo $! > /tmp/nsr-httpd.pid)")
    machine.wait_until_succeeds("ss -tln | grep -q ':${port}'")

    # Through the proxy: node-proxy's only path to the server is
    # HTTP_PROXY -> in-sandbox relay -> UDS -> host proxy -> server.
    out = run_user("node-proxy ${probes.proxyGet} 127.0.0.1 ${port}")
    assert "PROXIED_OK" in out, f"proxy path should reach the server, got: {out!r}"

    # Fail-closed: a DIRECT connect from the isolated netns cannot reach the
    # host-netns server (that loopback is a separate, empty netns). Only the
    # proxy works, so there is no other internet access.
    run_user("node-proxy ${probes.connect} 127.0.0.1 ${port}", succeed=False)

    # Kill by recorded PID (pkill -f on the store path would also match this
    # cleanup command's own argv).
    run_user("kill $(cat /tmp/nsr-httpd.pid) 2>/dev/null || true")
    run_user("rm -f /tmp/nsr-httpd.pid /tmp/nsr-httpd.log")
  '';
}
