// MCP client probe. Runs INSIDE opencode's sandbox (via `opencode-debug -c`), so it
// exercises the real host-tools-mcp server in the actual bwrap sandbox.
//
// It self-discovers the server the same way opencode does: read $OPENCODE_CONFIG and
// take `.mcp["host-tools-mcp"].command` as the argv to spawn (no hardcoded store path,
// no change to opencode/default.nix). It then drives the MCP stdio protocol
// (line-delimited JSON-RPC): initialize -> poll tools/list until a tool whose name
// contains req.substr appears (the host-side provider registers asynchronously) ->
// tools/call it with req.arguments -> print the result's text to stdout, and exit.
//
// The request (substr + arguments) is read from /tmp/host-tools-mcp/req.json, which the
// test writes on the host into the rw-shared dir, so nothing needs shell-quoting.
const fs = require("fs");
const { spawn } = require("child_process");

// Timestamped breadcrumbs to stderr (captured to /tmp/host-tools-mcp/err). Under
// aarch64 TCG the client can be very slow; if a wait times out the test dumps err,
// and these lines show how far the client got + how long each phase took.
const t0 = Date.now();
const log = (m) => console.error(`[mcpClient +${((Date.now() - t0) / 1000).toFixed(1)}s] ${m}`);

const req = JSON.parse(fs.readFileSync("/tmp/host-tools-mcp/req.json", "utf8"));
const cfg = JSON.parse(fs.readFileSync(process.env.OPENCODE_CONFIG, "utf8"));
const command = cfg.mcp["host-tools-mcp"].command;

log("spawning server: " + command.join(" "));
const srv = spawn(command[0], command.slice(1), { stdio: ["pipe", "pipe", "inherit"] });
log("server spawned pid=" + srv.pid);
srv.on("error", (e) => log("server spawn error: " + e));
srv.on("exit", (code, sig) => log(`server exited code=${code} sig=${sig}`));

// Reassemble line-delimited JSON-RPC messages from the server's stdout into a queue.
const queue = [];
let pending = "";
srv.stdout.on("data", (chunk) => {
  pending += chunk.toString();
  let nl;
  while ((nl = pending.indexOf("\n")) >= 0) {
    const line = pending.slice(0, nl);
    pending = pending.slice(nl + 1);
    if (!line.trim()) continue;
    try { queue.push(JSON.parse(line)); } catch (e) {}
  }
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function recvMatching(pred, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const i = queue.findIndex(pred);
    if (i >= 0) return queue.splice(i, 1)[0];
    if (Date.now() > deadline) throw new Error("timeout waiting for a matching message");
    await sleep(50);
  }
}

function send(obj) { srv.stdin.write(JSON.stringify(obj) + "\n"); }

function done(code) { try { srv.kill("SIGTERM"); } catch (e) {} process.exit(code); }
function fail(msg, code) { console.error(msg); done(code); }

(async () => {
  send({ jsonrpc: "2.0", id: 0, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "vm-test", version: "0.1.0" } } });
  await recvMatching((m) => m.id === 0, 15000);
  log("initialize acked");
  send({ jsonrpc: "2.0", method: "notifications/initialized" });

  // Poll tools/list until the host-registered tool shows up (absorbs the timing of the
  // provider connecting + registering after we initialize).
  let tool = null;
  let id = 1;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline && !tool) {
    const myId = id++;
    send({ jsonrpc: "2.0", id: myId, method: "tools/list" });
    const resp = await recvMatching((m) => m.id === myId, 5000);
    const tools = (resp.result && resp.result.tools) || [];
    tool = tools.find((t) => typeof t.name === "string" && t.name.indexOf(req.substr) >= 0) || null;
    if (!tool) await sleep(300);
  }
  if (!tool) fail("no tool matching substr appeared in tools/list", 3);
  log("tool found: " + tool.name);

  const callId = id++;
  send({ jsonrpc: "2.0", id: callId, method: "tools/call", params: { name: tool.name, arguments: req.arguments || {} } });
  const resp = await recvMatching((m) => m.id === callId, 20000);
  log("tool call returned");
  const content = (resp.result && resp.result.content) || [];
  const text = content.map((c) => (c && c.text) || "").join("\n");
  // An empty text must fail loudly: the tests assert on the output, and a silent
  // empty success is indistinguishable from a still-running client for a harness
  // that watches the output file.
  if (!text.trim()) fail("tool call returned empty text: " + JSON.stringify(resp.result), 4);
  process.stdout.write(text, () => done(0));
})().catch((e) => fail(String(e), 1));
