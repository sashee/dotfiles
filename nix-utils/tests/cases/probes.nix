# Shared probe scripts used by the sandbox test cases. Each is a JS file run via
# the sandboxed `node`/`node-nonet` (referenced by store path, so no shell quoting).
{ pkgs }:
{
  # Print the file named by argv[2] (relative to cwd) to stdout.
  readFile = pkgs.writeText "readFile.js" ''
    const fs = require("fs");
    process.stdout.write(fs.readFileSync(process.argv[2], "utf8"));
  '';

  # JSON-print the entries of the directory named by argv[2] (or ERR:<code>).
  listDir = pkgs.writeText "listDir.js" ''
    const fs = require("fs");
    try { process.stdout.write(JSON.stringify(fs.readdirSync(process.argv[2]))); }
    catch (e) { process.stdout.write("ERR:" + e.code); }
  '';

  # mkdir -p dirname(argv[2]) then write a marker file at argv[2].
  writeFile = pkgs.writeText "writeFile.js" ''
    const fs = require("fs");
    const path = require("path");
    const target = process.argv[2];
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, "nsr\n");
  '';

  # Try to create+bind an AF_INET (udp4) socket. Exit 0 if it binds, 1 on error
  # (seccomp blocks socket(AF_INET) with EACCES for no-network tools).
  bindUdp = pkgs.writeText "bindUdp.js" ''
    const dgram = require("dgram");
    const s = dgram.createSocket("udp4");
    s.on("error", (e) => { console.error("ERR", e.code); process.exit(1); });
    s.bind(0, "127.0.0.1", () => { console.error("BOUND"); s.close(); process.exit(0); });
  '';

  # TCP server: argv[2]=host, argv[3]=port. Runs until killed.
  server = pkgs.writeText "server.js" ''
    const net = require("net");
    const host = process.argv[2];
    const port = parseInt(process.argv[3], 10);
    const srv = net.createServer((c) => { c.end("ok\n"); });
    srv.on("error", (e) => { console.error("SRVERR", e.code); process.exit(1); });
    srv.listen(port, host, () => { console.error("LISTENING"); });
  '';

  # TCP client: argv[2]=host, argv[3]=port. Exit 0 if connected, 1 on error.
  connect = pkgs.writeText "connect.js" ''
    const net = require("net");
    const host = process.argv[2];
    const port = parseInt(process.argv[3], 10);
    const s = net.connect(port, host, () => { process.stdout.write("connected\n"); s.end(); process.exit(0); });
    s.on("error", (e) => { console.error("ERR", e.code); process.exit(1); });
    s.setTimeout(5000, () => { console.error("TIMEOUT"); process.exit(2); });
  '';

  # Print /etc/machine-id.
  printMachineId = pkgs.writeText "printMachineId.js" ''
    process.stdout.write(require("fs").readFileSync("/etc/machine-id", "utf8"));
  '';

  # Print the comm (process name) of every visible PID, one per line.
  procComms = pkgs.writeText "procComms.js" ''
    const fs = require("fs");
    const out = [];
    for (const p of fs.readdirSync("/proc")) {
      if (/^\d+$/.test(p)) {
        try { out.push(fs.readFileSync("/proc/" + p + "/comm", "utf8").trim()); } catch (e) {}
      }
    }
    process.stdout.write(out.join("\n"));
  '';
}
