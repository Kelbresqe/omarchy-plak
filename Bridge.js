// Bridge.js — the QML side of the bridge protocol, kept free of Qt so node
// can test it. One request → one response matched by id; events are
// unsolicited lines with an `ev` field.

function newClient() {
  return { nextId: 0, pending: {} }
}

// Build the line for a request and remember its callback.
function encode(client, op, arg, cb) {
  client.nextId += 1
  var id = client.nextId
  var msg = { id: id, op: op }
  if (arg) for (var k in arg) if (k !== "id" && k !== "op") msg[k] = arg[k]
  client.pending[id] = { cb: cb || null, op: op, at: Date.now() }
  return { id: id, line: JSON.stringify(msg) + "\n" }
}

// One line from the socket → { kind: "response"|"event"|"junk", msg, cb, op }
// A response's callback is removed from `pending` here; the caller invokes it.
function decode(client, line) {
  var msg
  try { msg = JSON.parse(String(line || "").trim()) } catch (e) { return { kind: "junk", msg: null } }
  if (!msg || typeof msg !== "object") return { kind: "junk", msg: null }
  if (msg.ev) return { kind: "event", msg: msg }
  if (msg.id !== undefined && client.pending[msg.id]) {
    var p = client.pending[msg.id]
    delete client.pending[msg.id]
    return { kind: "response", msg: msg, cb: p.cb, op: p.op }
  }
  return { kind: "junk", msg: msg }
}

// Drop requests older than `maxAgeMs`, returning their callbacks so the UI
// can be told. Called when the socket drops: nothing will answer them.
function expire(client, maxAgeMs, now) {
  now = now || Date.now()
  var out = []
  for (var id in client.pending) {
    if (now - client.pending[id].at >= maxAgeMs) {
      out.push({ id: Number(id), cb: client.pending[id].cb, op: client.pending[id].op })
      delete client.pending[id]
    }
  }
  return out
}

// {link, app} → next {link, app} given a socket event or bridge message.
// `link` is whether the socket is up; `app` is the bridge's view of the
// browser. When the link is down the app state is unknowable, so it resets.
function reduce(state, input) {
  var next = { link: state.link, app: state.app, pid: state.pid || 0, video: state.video || "" }
  if (input.socket === "connected") next.link = "up"
  else if (input.socket === "disconnected") { next.link = "down"; next.app = "bridge-down"; next.pid = 0 }
  else if (input.msg) {
    var m = input.msg
    if (m.ev === "state" || (m.ok && m.state)) {
      next.app = String(m.state)
      if (m.pid !== undefined) next.pid = Number(m.pid) || 0
      if (m.video !== undefined) next.video = String(m.video || "")
    }
    if (m.ev === "track") next.video = String(m.video || "")
  }
  return next
}

// A human line for each state, and the single action that fixes it.
function describe(app, link) {
  if (link !== "up" || app === "bridge-down") return { text: "Starting the bridge…", action: "" }
  if (app === "no-app") return { text: "YouTube Music is not open", action: "launch" }
  if (app === "attaching") return { text: "Connecting to YouTube Music…", action: "" }
  // Google refuses to sign in the remote-controlled app window, so signing in
  // goes through a plain browser window (bridge op app.signin).
  if (app === "signed-out") return { text: "Not signed in to YouTube Music", action: "signin" }
  if (app === "signing-in") return { text: "Sign in in the Google window, then close it. TekTube reopens by itself.", action: "" }
  return { text: "", action: "" }
}

if (typeof module !== "undefined") {
  module.exports = { newClient: newClient, encode: encode, decode: decode, expire: expire, reduce: reduce, describe: describe }
}
