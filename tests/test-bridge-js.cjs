const assert = require("node:assert/strict")
const B = require("../Bridge.js")
let n = 0
function t(name, fn) { n++; try { fn() } catch (e) { console.error("FAIL", name); throw e } }

t("ids increment and lines are JSON + newline", () => {
  const c = B.newClient()
  const a = B.encode(c, "state", null, () => {})
  const b = B.encode(c, "play", { list: "PL12345678", id: 99, op: "hijack" }, () => {})
  assert.equal(a.id, 1); assert.equal(b.id, 2)
  assert.deepEqual(JSON.parse(b.line), { id: 2, op: "play", list: "PL12345678" })
  assert.equal(b.line.endsWith("\n"), true)
})

t("responses route to their callback once", () => {
  const c = B.newClient()
  let got = null
  B.encode(c, "queue", null, m => { got = m })
  const r = B.decode(c, '{"id":1,"ok":true,"data":{"x":1}}')
  assert.equal(r.kind, "response"); assert.equal(r.op, "queue")
  r.cb(r.msg); assert.deepEqual(got.data, { x: 1 })
  assert.equal(B.decode(c, '{"id":1,"ok":true}').kind, "junk")
})

t("events and junk", () => {
  const c = B.newClient()
  assert.equal(B.decode(c, '{"ev":"track","video":"abc"}').kind, "event")
  assert.equal(B.decode(c, "not json").kind, "junk")
  assert.equal(B.decode(c, "").kind, "junk")
  assert.equal(B.decode(c, "[1,2]").kind, "junk")
})

t("expire returns stale callbacks", () => {
  const c = B.newClient()
  B.encode(c, "a", null, () => {}); B.encode(c, "b", null, () => {})
  c.pending[1].at = 0
  const ex = B.expire(c, 1000, 5000)
  assert.equal(ex.length, 1); assert.equal(ex[0].op, "a")
  assert.deepEqual(Object.keys(c.pending), ["2"])
})

t("reducer", () => {
  let s = { link: "down", app: "bridge-down" }
  s = B.reduce(s, { socket: "connected" }); assert.equal(s.link, "up")
  s = B.reduce(s, { msg: { id: 1, ok: true, state: "ready", pid: 4242, video: "v1" } })
  assert.equal(s.app, "ready"); assert.equal(s.pid, 4242); assert.equal(s.video, "v1")
  s = B.reduce(s, { msg: { ev: "track", video: "v2" } }); assert.equal(s.video, "v2")
  s = B.reduce(s, { msg: { ev: "state", state: "no-app", pid: 0 } }); assert.equal(s.app, "no-app")
  s = B.reduce(s, { socket: "disconnected" }); assert.equal(s.app, "bridge-down"); assert.equal(s.link, "down")
})

t("describe", () => {
  assert.equal(B.describe("no-app", "up").action, "launch")
  assert.equal(B.describe("signed-out", "up").action, "reveal")
  assert.equal(B.describe("ready", "up").text, "")
  assert.equal(B.describe("ready", "down").action, "")
})
console.log("test-bridge-js: " + n + " passed")
