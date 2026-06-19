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

  # Try to create a socket of the family named by argv[2] (udp4 / udp6 / unix) and
  # print "OK" if created, else "ERR:<code>" — then exit 0. The seccomp filter fails
  # socket(family) with EACCES for blocked families, so "ERR:EACCES" means the family
  # was blocked by seccomp (vs a later addressing/connect failure, which has another
  # code). Used to probe a tool's seccomp filter via `<tool>-debug -c 'node ...'`.
  socketFamily = pkgs.writeText "socketFamily.js" ''
    const fam = process.argv[2];
    const done = (s) => { process.stdout.write(s); process.exit(0); };
    if (fam === "unix") {
      const net = require("net");
      const srv = net.createServer();
      srv.on("error", (e) => done("ERR:" + e.code));
      srv.listen("\0nsr-seccomp-probe", () => { srv.close(); done("OK"); });
    } else {
      const dgram = require("dgram");
      const sock = dgram.createSocket(fam === "udp6" ? "udp6" : "udp4");
      sock.on("error", (e) => done("ERR:" + e.code));
      sock.bind(0, fam === "udp6" ? "::1" : "127.0.0.1", () => { sock.close(); done("OK"); });
    }
  '';

  # Print the value of __NIX_UTILS_SKIP_SANDBOX in this process's environment.
  printSkip = pkgs.writeText "printSkip.js" ''
    process.stdout.write(process.env.__NIX_UTILS_SKIP_SANDBOX || "<unset>");
  '';

  # Exec argv[2] with argv[3..] as a child (inheriting env), forwarding its exit
  # status — used to run a nested tool from inside a sandboxed tool.
  reuseProbe = pkgs.writeText "reuseProbe.js" ''
    const { execFileSync } = require("child_process");
    execFileSync(process.argv[2], process.argv.slice(3), { stdio: "inherit" });
  '';

  # Report privilege state: /proc/self/status Uid/CapEff/NoNewPrivs and whether
  # setuid(0) is permitted. JSON to stdout.
  privCheck = pkgs.writeText "privCheck.js" ''
    const fs = require("fs");
    const lines = fs.readFileSync("/proc/self/status", "utf8").split("\n");
    const get = (k) => { const l = lines.find((x) => x.startsWith(k + ":")); return l ? l.slice(k.length + 1).trim() : ""; };
    let setuid;
    try { process.setuid(0); setuid = "ESCALATED"; } catch (e) { setuid = "denied:" + e.code; }
    process.stdout.write(JSON.stringify({ uid: get("Uid"), capeff: get("CapEff"), nnp: get("NoNewPrivs"), setuid }));
  '';

  # Listen on an abstract-namespace unix socket named "\0<argv[2]>". Runs until
  # killed. (In Node a leading NUL in the path = the Linux abstract namespace.)
  abstractServer = pkgs.writeText "abstractServer.js" ''
    const net = require("net");
    const name = "\0" + process.argv[2];
    const srv = net.createServer((c) => c.end("ok\n"));
    srv.on("error", (e) => { console.error("SRVERR", e.code); process.exit(1); });
    srv.listen(name, () => console.error("LISTENING"));
  '';

  # Connect to the abstract socket "\0<argv[2]>". Exit 0 on connect, 1 on error.
  abstractConnect = pkgs.writeText "abstractConnect.js" ''
    const net = require("net");
    const name = "\0" + process.argv[2];
    const s = net.connect(name, () => { process.stdout.write("connected\n"); s.end(); process.exit(0); });
    s.on("error", (e) => { console.error("ERR", e.code); process.exit(1); });
    s.setTimeout(3000, () => { console.error("TIMEOUT"); process.exit(2); });
  '';

  # Print (one per line) the abstract-namespace sockets in this netns that are
  # stream/seqpacket *listeners* (SO_ACCEPTON = flags & 0x10000) — i.e. connectable
  # services. /proc/net/unix shows the network namespace's sockets.
  auditAbstractListeners = pkgs.writeText "auditAbstractListeners.js" ''
    const fs = require("fs");
    const out = [];
    for (const line of fs.readFileSync("/proc/net/unix", "utf8").split("\n").slice(1)) {
      const f = line.trim().split(/\s+/);
      if (f.length < 8) continue;
      const flags = parseInt(f[3], 16);
      const p = f[7];
      if (p && p.startsWith("@") && (flags & 0x10000)) out.push(p);
    }
    process.stdout.write([...new Set(out)].sort().join("\n"));
  '';

  # Walk the argv roots for unix-domain sockets and print (one per line) only the
  # ones this uid can actually connect() to — i.e. connect doesn't fail with EACCES
  # (CONNECTED / ECONNREFUSED / EPROTOTYPE all mean "reachable"). Visible-but-
  # permission-blocked sockets are excluded. connect+close is harmless (no method
  # is sent). Used to audit the reachable socket surface against a baseline.
  auditConnectable = pkgs.writeText "auditConnectable.js" ''
    const net = require("net"), fs = require("fs"), path = require("path");
    const socks = [];
    function walk(d) {
      let ents; try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (e) { return; }
      for (const x of ents) {
        const p = path.join(d, x.name);
        let st; try { st = fs.lstatSync(p); } catch (e) { continue; }
        if (st.isSocket()) socks.push(p);
        else if (st.isDirectory() && !st.isSymbolicLink()) walk(p);
      }
    }
    for (const r of process.argv.slice(2)) walk(r);
    socks.sort();
    function probe(p) {
      return new Promise((res) => {
        const s = net.connect(p);
        let done = false;
        const fin = (reachable) => { if (done) return; done = true; try { s.destroy(); } catch (e) {} res(reachable ? p : null); };
        s.on("connect", () => fin(true));
        s.on("error", (e) => fin(e.code !== "EACCES"));
        setTimeout(() => fin(true), 1500); // timed out = reachable enough to worry about
      });
    }
    (async () => {
      const out = [];
      for (const p of socks) { const r = await probe(p); if (r) out.push(r); }
      process.stdout.write(out.join("\n"));
    })();
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
