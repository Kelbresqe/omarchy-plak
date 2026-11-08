import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons as Commons
import "Bridge.js" as Bridge
import "Ytm.js" as Ytm

// The plugin's one long-lived object. It supervises bin/ytm-bridge, owns the
// socket to it, picks the MPRIS player that belongs to *our* browser window,
// and holds the shared state the bar widget and the panel both render.
//
// Two sources, deliberately kept apart:
//   - MPRIS (`player`): play state, art, position, transport. Always on; it
//     is what the shell's own media widget uses, so it cannot be less
//     reliable than that.
//   - the bridge (`request`): playlists, queue, lyrics, likes — the account
//     data MPRIS does not carry. If it is down the widget degrades to a
//     plain controller, never to blank.
Item {
  id: root

  property var shell: null
  // The bar widget pushes its settings here; services get none of their own.
  property var settings: ({})
  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property string pluginDir: {
    var p = decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
    return p.replace(/\/$/, "")
  }
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string socketPath: runtimeDir + "/tiertek.ytm.sock"

  // ---------------------------------------------------------------- state

  property string link: "down"          // socket to the bridge
  property string app: "bridge-down"    // bridge's view of the browser
  property int pid: 0                   // our browser's pid, for MPRIS matching
  property string video: ""             // current videoId, from the page
  readonly property bool ready: link === "up" && app === "ready"

  property var client: Bridge.newClient()

  property var home: []                 // Ytm.parseHome output
  property bool homeLoading: false
  property var library: []              // Ytm.parsePlaylists output
  property bool libraryCached: false
  property bool libraryLoading: false
  property var queue: ({ items: [], current: -1 })
  property var lyrics: null             // Ytm.parseLyrics output for lyricsVideo
  property string lyricsVideo: ""
  property bool lyricsLoading: false
  property string liked: ""             // LIKE / DISLIKE / INDIFFERENT for `video`
  property string lastError: ""

  signal trackChanged(string video)

  // The bar widget tells us when its panel is showing; toasts stay quiet then.
  property bool panelOpen: false

  function applyState(next) {
    var was = root.app
    var wasVideo = root.video
    root.link = next.link
    root.app = next.app
    root.pid = next.pid
    root.video = next.video
    if (root.app === "ready" && was !== "ready") {
      root.loadLibrary()
      root.loadHome()
      root.loadVolume()
      root.loadRepeat()
      root.loadShuffle()
      root.loadResume()
      root.onTrack(root.video)
    }
    // Volume / repeat / shuffle keep their last known values while the page
    // is away (the controls show them, disabled), instead of vanishing.
    if (root.video !== wasVideo) root.onTrack(root.video)
  }

  // Settings the bridge remembered from the last session ({volume, repeat,
  // shuffle}), applied only where nothing better is known yet, so the panel
  // shows its controls right after the shell (re)starts.
  function applyMemo(memo) {
    if (!memo) return
    if (root.volume < 0 && typeof memo.volume === "number") root.volume = Math.max(0, Math.min(1, memo.volume / 100))
    if (root.repeatMode === "" && (memo.repeat === "NONE" || memo.repeat === "ALL" || memo.repeat === "ONE")) root.repeatMode = memo.repeat
    if (root.shuffleState < 0 && typeof memo.shuffle === "boolean") root.shuffleState = memo.shuffle ? 1 : 0
  }

  // ---------------------------------------------------------------- strings

  // The plugin's own strings (i18n/<language>.json), following
  // Setup > Language live; English is the fallback for anything missing.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function tr(key, fallback) { return strings.t(key, fallback) }
  function trn(key, count, fallback) { return strings.tn(key, count, fallback) }

  function currentState() {
    return { link: root.link, app: root.app, pid: root.pid, video: root.video }
  }

  // ---------------------------------------------------------------- MPRIS

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: pickPlayer(players, pid)

  // Only the player whose bus name carries our browser's pid. There is no
  // safe guess without it: MPRIS cannot tell this window from the user's
  // everyday Chrome, and driving the wrong one is worse than showing idle.
  function pickPlayer(list, wantPid) {
    if (!wantPid) return null
    var suffix = ".instance" + wantPid
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (p && String(p.dbusName || "").indexOf(suffix, String(p.dbusName || "").length - suffix.length) !== -1) return p
    }
    return null
  }

  readonly property bool hasMedia: player !== null && !!(player.trackTitle || player.trackArtist)
  readonly property bool isPlaying: player !== null && player.isPlaying
  readonly property string title: player ? String(player.trackTitle || "") : ""
  readonly property string artist: player ? String(player.trackArtist || "") : ""
  readonly property string album: player ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: player ? String(player.trackArtUrl || "") : ""

  // MPRIS only pushes the position on seek. Quickshell interpolates it when
  // positionChanged() is signalled, so poll while playing — it is what keeps
  // the seek bar, the bar ring and the lyric highlight moving.
  Timer {
    interval: 1000
    repeat: true
    running: root.isPlaying
    triggeredOnStart: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  function togglePlaying() { if (player) player.togglePlaying() }
  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }
  function seekTo(seconds) { if (player && player.canSeek) player.position = seconds }
  // ← / → in Now playing.
  function seekBy(delta) {
    if (!player || !player.canSeek) return
    var end = player.lengthSupported && player.length > 0 ? player.length - 1 : Infinity
    player.position = Math.max(0, Math.min(end, player.position + delta))
  }

  // Volume, 0–1. Chromium's MPRIS player advertises Volume and accepts a
  // write, but ignores it and always reads back 1.0 — so volume goes through
  // the page's own slider via the bridge instead. -1 while unknown.
  // *Known drives whether a control is shown, *Supported whether it acts.
  property real volume: -1
  readonly property bool volumeKnown: root.volume >= 0
  readonly property bool volumeSupported: root.ready && root.volumeKnown

  function loadVolume() {
    root.request("volume.get", null, function(m) {
      if (m.ok && m.data && typeof m.data.volume === "number") root.volume = Math.max(0, Math.min(1, m.data.volume / 100))
    })
  }
  function setVolume(v) {
    if (!root.volumeSupported) return
    v = Math.max(0, Math.min(1, v))
    root.volume = v                                     // optimistic
    root.request("volume.set", { volume: Math.round(v * 100) }, function(m) { if (!m.ok) root.loadVolume() })
  }
  // Bar wheel and the volume keys. Shows Omarchy's OSD with the media icon,
  // so it reads as the music's level rather than the system volume.
  function nudgeVolume(delta) {
    if (!root.volumeSupported) return
    root.setVolume(root.volume + delta)
    Quickshell.execDetached(["omarchy-osd", "-i", "media", "-p", String(Math.round(root.volume * 100))])
  }
  // Repeat: NONE / ALL / ONE, read from and set through the page's player bar
  // (Chromium's MPRIS player has no LoopStatus). "" until the page answers.
  property string repeatMode: ""
  readonly property bool repeatKnown: root.repeatMode !== ""
  readonly property bool repeatSupported: root.ready && root.repeatKnown

  function loadRepeat() {
    root.request("repeat.get", null, function(m) {
      if (m.ok && m.data) root.repeatMode = String(m.data.mode || "")
    })
  }
  // Same order as the site's own button: off → all → one → off.
  function cycleRepeat() {
    if (!root.repeatSupported) return
    var next = { NONE: "ALL", ALL: "ONE", ONE: "NONE" }[root.repeatMode] || "NONE"
    root.repeatMode = next                              // optimistic
    root.request("repeat.set", { mode: next }, function(m) {
      if (m.ok && m.data && m.data.mode) root.repeatMode = String(m.data.mode)
      else root.loadRepeat()
    })
  }

  // Shuffle: a toggle on the page's player bar (Chromium's MPRIS player has
  // no Shuffle). -1 unknown, 0 off, 1 on.
  property int shuffleState: -1
  readonly property bool shuffleKnown: root.shuffleState >= 0
  readonly property bool shuffleSupported: root.ready && root.shuffleKnown
  readonly property bool shuffleOn: root.shuffleState === 1

  function applyShuffle(m) {
    if (m.ok && m.data && typeof m.data.on === "boolean") { root.shuffleState = m.data.on ? 1 : 0; return true }
    return false
  }
  function loadShuffle() { root.request("shuffle.get", null, root.applyShuffle) }
  function toggleShuffle() {
    if (!root.shuffleSupported) return
    var next = !root.shuffleOn
    root.shuffleState = next ? 1 : 0                    // optimistic
    root.request("shuffle.set", { on: next }, function(m) {
      if (!root.applyShuffle(m)) root.loadShuffle()
      queueRefresh.restart()                            // the up-next order changed
    })
  }

  // The track the last session ended on, offered while nothing plays:
  // {video, list, time, title, artist}, or null.
  property var resume: null
  function loadResume() {
    root.request("resume.get", null, function(m) { root.resume = m.ok && m.resume && !root.video ? m.resume : null })
  }
  function resumePlay() {
    if (!root.resume || !root.ready) return
    root.resume = null
    root.request("resume.play", null, null)
  }

  // Pick up a change made in the YouTube Music window itself.
  onPanelOpenChanged: if (root.panelOpen && root.ready) {
    root.loadVolume(); root.loadRepeat(); root.loadShuffle()
    if (!root.video) root.loadResume()
  }

  // ---------------------------------------------------------------- bridge process

  property int restartDelayMs: 1000

  // True once our bridge has said it is listening. The socket is only tried
  // after that: connecting earlier races the bridge's startup, and on
  // Quickshell < 0.3.2 a Socket whose first connect failed never recovers
  // (fixed upstream in quickshell 41651d7d, "discard sockets which have
  // failed to connect"), which left the panel on "Starting the bridge…"
  // for good (upstream issue #1).
  property bool bridgeListening: false

  Process {
    id: bridgeProc
    command: ["python3", root.pluginDir + "/bin/ytm-bridge"]
    running: true
    stderr: SplitParser {
      onRead: data => {
        var line = String(data)
        if (line.indexOf("listening on") !== -1) root.bridgeListening = true
        if (line.indexOf("state ") === -1) console.log("[tiertek.ytm] " + line)
      }
    }
    onExited: (code, status) => {
      root.bridgeListening = false
      // Crash loop guard: 1 s → 30 s.
      restartTimer.interval = root.restartDelayMs
      root.restartDelayMs = Math.min(30000, root.restartDelayMs * 2)
      restartTimer.start()
    }
    onStarted: root.restartDelayMs = 1000
  }

  Timer {
    id: restartTimer
    repeat: false
    onTriggered: bridgeProc.running = true
  }

  // ---------------------------------------------------------------- socket

  Socket {
    id: sock
    path: root.socketPath
    connected: false
    parser: SplitParser {
      onRead: data => root.onLine(data)
    }
    onConnectionStateChanged: {
      root.applyState(Bridge.reduce(root.currentState(), { socket: sock.connected ? "connected" : "disconnected" }))
      if (sock.connected) {
        root.request("state", null, function(m) { if (m.ok) root.applyMemo(m.memo) })
      } else {
        var dropped = Bridge.expire(root.client, 0)
        for (var i = 0; i < dropped.length; i++) if (dropped[i].cb) dropped[i].cb({ ok: false, error: "bridge-down" })
      }
    }
  }

  Timer {
    id: reconnect
    interval: 2000
    repeat: true
    running: !sock.connected && root.bridgeListening
    triggeredOnStart: true
    onTriggered: sock.connected = true
  }

  // While the browser is not attached, ask now and then; events cover the rest.
  Timer {
    interval: 5000
    repeat: true
    running: sock.connected && root.app !== "ready"
    onTriggered: root.request("state", null, null)
  }

  function request(op, arg, cb) {
    if (!sock.connected) {
      if (cb) cb({ ok: false, error: "bridge-down" })
      return
    }
    var r = Bridge.encode(root.client, op, arg, cb)
    sock.write(r.line)
  }

  function onLine(line) {
    var d = Bridge.decode(root.client, line)
    if (d.kind === "junk") return
    root.applyState(Bridge.reduce(root.currentState(), { msg: d.msg }))
    // The bridge restored repeat / shuffle from the last session.
    if (d.kind === "event" && d.msg.ev === "player") { root.loadRepeat(); root.loadShuffle() }
    if (d.kind === "response") {
      if (d.msg.ok === false && d.msg.error === "page-error") root.lastError = d.op
      if (d.cb) d.cb(d.msg)
    }
  }

  // ---------------------------------------------------------------- data

  function loadLibrary() {
    if (root.libraryLoading) return
    root.libraryLoading = true
    root.request("library.playlists", null, function(m) {
      root.libraryLoading = false
      if (!m.ok) return
      root.library = Ytm.parsePlaylists(m.data)
      root.libraryCached = !!m.cached
    })
  }

  function loadHome() {
    if (root.homeLoading) return
    root.homeLoading = true
    root.request("home", null, function(m) {
      root.homeLoading = false
      if (m.ok) root.home = Ytm.parseHome(m.data)
    })
  }

  // Play any tile the UI hands us. Albums carry a browse id, not a playlist
  // id; the album page's canonical URL has the one the player wants.
  function playItem(item) {
    if (!item) return
    if (item.kind === "song") { root.play(item.list, item.videoId, false); return }
    if (item.kind === "album") {
      root.loadPlaylist(item.list, function(r) {
        if (r && r.playlistId) root.play(r.playlistId, "", false)
        else if (r && r.items.length) root.play("", r.items[0].videoId, false)
      })
      return
    }
    root.play(item.list, "", false)
  }

  function loadPlaylist(listId, cb) {
    root.request("playlist.items", { list: listId }, function(m) {
      cb(m.ok ? Ytm.parsePlaylistItems(m.data) : null)
    })
  }

  function loadQueue() {
    root.request("queue", null, function(m) {
      if (m.ok) root.queue = Ytm.parseQueue(m.data, root.video)
    })
  }

  function loadLyrics(videoId) {
    if (!Ytm.isValidId(videoId)) { root.lyrics = null; root.lyricsVideo = ""; return }
    if (root.lyricsVideo === videoId && root.lyrics) return
    root.lyricsLoading = true
    root.lyricsVideo = videoId
    root.request("lyrics", { video: videoId }, function(m) {
      root.lyricsLoading = false
      if (root.lyricsVideo !== videoId) return   // track moved on meanwhile
      root.lyrics = m.ok ? Ytm.parseLyrics(m.data) : { timed: null, plain: null, source: "" }
    })
  }

  function refreshLiked() {
    root.request("now", null, function(m) {
      if (m.ok && m.data) root.liked = String(m.data.liked || "")
    })
  }

  function onTrack(videoId) {
    root.liked = ""
    root.lyrics = null
    root.lyricsVideo = ""
    if (videoId) root.resume = null
    else if (root.ready) root.loadResume()
    if (!videoId || !root.ready) return
    queueRefresh.restart()
    root.refreshLiked()
    root.loadRepeat()      // a `play` reloads the page, which may reset these
    root.loadShuffle()
    root.trackChanged(videoId)
  }

  // The DOM queue re-renders a moment after the URL changes.
  Timer {
    id: queueRefresh
    interval: 1500
    repeat: false
    onTriggered: root.loadQueue()
  }

  // ---------------------------------------------------------------- actions

  function play(listId, videoId, shuffle) {
    var arg = {}
    if (listId) arg.list = listId
    if (videoId) arg.video = videoId
    if (shuffle) arg.shuffle = true
    root.request("play", arg, null)
  }

  function radio(videoId) { root.request("radio", { video: videoId }, null) }

  function queueJump(index) { root.request("queue.jump", { index: index }, function(m) { queueRefresh.restart() }) }

  function toggleLike() {
    if (!root.video) return
    var op = root.liked === "LIKE" ? "unlike" : "like"
    var v = root.video
    root.liked = op === "like" ? "LIKE" : "INDIFFERENT"   // optimistic
    root.request(op, { video: v }, function(m) { if (!m.ok) root.refreshLiked() })
  }

  function dislike() {
    if (!root.video) return
    root.liked = "DISLIKE"
    root.request("dislike", { video: root.video }, function(m) { if (!m.ok) root.refreshLiked() })
  }

  function addToPlaylist(videoId, listId, cb) {
    root.request("playlist.add", { video: videoId, list: listId }, function(m) { if (cb) cb(m.ok) })
  }

  function search(q, cb) {
    root.request("search", { q: q }, function(m) { cb(m.ok ? Ytm.parseSearch(m.data) : null) })
  }

  function launchApp() {
    root.quitRequested = false
    root.holdNextWindow(true)
    var arg = {}
    var b = String(root.setting("browser", "") || "")
    if (b !== "") arg.browser = b
    root.request("app.launch", arg, null)
  }

  // Close the app window to free its memory (~700 MB measured); the sign-in
  // stays in the profile, so launchApp() brings it back signed in. Holds off
  // autoRelaunch until the next launch.
  property bool quitRequested: false
  function quitApp() {
    root.quitRequested = true
    root.request("app.quit", null, null)
  }

  // Close the app window and sign in through a plain one (see bin/ytm-app
  // --signin); the bridge reports "signing-in" until that window closes.
  function signIn() {
    root.quitRequested = false
    var arg = {}
    var b = String(root.setting("browser", "") || "")
    if (b !== "") arg.browser = b
    root.request("app.signin", arg, null)
  }

  // ---------------------------------------------------------------- toast

  // One replaceable notification per track change while playing. Chromium
  // hands MPRIS the artwork as a local file, so it goes straight to
  // notify-send; an https URL is fetched into the cache by the bridge.
  Timer {
    id: toastDelay
    interval: 1200          // let MPRIS metadata catch up with the page
    repeat: false
    onTriggered: root.toastNow()
  }
  onTrackChanged: if (root.setting("toast", true)) toastDelay.restart()

  function toastNow() {
    if (!root.setting("toast", true) || root.panelOpen || !root.isPlaying || !root.title) return
    var art = root.artUrl
    if (art.indexOf("file://") === 0) root.sendToast(decodeURIComponent(art.slice(7)))
    else if (art.indexOf("https://") === 0) root.request("art", { url: art }, function(m) { root.sendToast(m.ok ? m.path : "") })
    else root.sendToast("")
  }

  function sendToast(iconPath) {
    if (toastProc.running) return
    var cmd = ["notify-send", "--app-name=TekTube",
               "--hint=string:x-canonical-private-synchronous:tiertek.ytm", "--expire-time=4000"]
    if (iconPath) cmd.push("--icon=" + iconPath)
    cmd.push(root.title, root.artist + (root.album && root.album !== root.title ? "  ·  " + root.album : ""))
    toastProc.command = cmd
    toastProc.running = true
  }
  Process { id: toastProc }

  // ---------------------------------------------------------------- sleep timer

  property double sleepUntil: 0          // epoch ms, 0 = off
  readonly property int sleepMinutesLeft: sleepUntil > 0 ? Math.max(0, Math.ceil((sleepUntil - sleepTick.now) / 60000)) : 0

  function setSleep(minutes) {
    root.sleepUntil = minutes > 0 ? Date.now() + minutes * 60000 : 0
    sleepTick.now = Date.now()
  }
  // Cycles 15 → 30 → 60 → off, the way a bedside radio does.
  function cycleSleep() {
    var left = root.sleepMinutesLeft
    root.setSleep(left === 0 ? 15 : left <= 15 ? 30 : left <= 30 ? 60 : 0)
  }
  Timer {
    id: sleepTick
    property double now: Date.now()
    interval: 5000
    repeat: true
    running: root.sleepUntil > 0
    onTriggered: {
      now = Date.now()
      if (now >= root.sleepUntil) {
        root.sleepUntil = 0
        if (root.player && root.player.isPlaying) root.player.pause()
      }
    }
  }

  // ---------------------------------------------------------------- auto relaunch

  // Off by default: silently reopening a browser the user just closed is
  // exactly the behaviour people uninstall things over.
  property double lastRelaunchMs: 0
  onAppChanged: {
    if (root.app === "no-app" && root.wasReady && root.setting("autoRelaunch", false)
        && !root.quitRequested && Date.now() - root.lastRelaunchMs > 60000) {
      root.lastRelaunchMs = Date.now()
      root.launchApp()
    }
    // ytm-app --signin relaunches the app window on its own once the
    // sign-in window closes; have the rule ready for it.
    if (root.app === "signing-in") root.holdNextWindow(true)
    root.wasReady = root.app === "ready" || (root.wasReady && root.app === "attaching")
  }
  property bool wasReady: false

  // ---------------------------------------------------------------- cava

  // Spectrum bars for the player view. Only runs while the panel is open on
  // a playing track, and only if cava is installed; otherwise it simply
  // never appears.
  property var spectrum: []
  property bool cavaWanted: false
  property bool cavaMissing: true          // until the probe says otherwise
  readonly property string cavaConfig: root.pluginDir + "/bin/cava.conf"

  // Probe once; Quickshell logs a warning for every failed process start,
  // and a missing optional dependency should not fill the journal.
  Process {
    id: cavaProbe
    command: ["which", "cava"]
    running: true
    onExited: (code, status) => { root.cavaMissing = code !== 0 }
  }

  Process {
    id: cavaProc
    command: ["cava", "-p", root.cavaConfig]
    running: root.cavaWanted && root.isPlaying && !root.cavaMissing && root.setting("visualizer", true)
    stdout: SplitParser {
      onRead: data => {
        var parts = String(data).split(";")
        var out = []
        for (var i = 0; i < parts.length; i++) { var n = parseInt(parts[i], 10); if (!isNaN(n)) out.push(n / 100) }
        if (out.length) root.spectrum = out
      }
    }
    onExited: (code, status) => { root.spectrum = [] }
  }
  onCavaWantedChanged: if (!cavaWanted) root.spectrum = []

  // ---------------------------------------------------------------- window

  // Wayland ignores Chromium's --class; the app window is identified by the
  // app id Chromium derives from the URL: "<browser>-music.youtube.com__-Default".
  readonly property string windowClassMatch: "-music.youtube.com__"
  readonly property var toplevels: Hyprland.toplevels ? Hyprland.toplevels.values : []
  readonly property var appWindow: {
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      var ipc = t && t.lastIpcObject ? t.lastIpcObject : {}
      if (String(ipc["class"] || "").indexOf(root.windowClassMatch) !== -1) return t
    }
    return null
  }
  readonly property bool appWindowPresent: appWindow !== null

  function dispatch(expr) { Quickshell.execDetached(["hyprctl", "dispatch_lua_expression", expr]) }
  function windowSelector() { return "[[class:^(.*" + root.windowClassMatch.replace(/\./g, "\\.") + ".*)$]]" }

  function revealApp() {
    if (!root.appWindowPresent) { root.launchApp(); return }
    root.dispatch("hl.dsp.workspace.toggle_special([[ytm]])")
  }

  function hideApp() {
    if (!root.appWindowPresent) return
    root.dispatch("hl.dsp.window.move({ window = " + root.windowSelector() + ", workspace = [[special:ytm]], follow = false })")
  }

  // Park a freshly mapped app window out of the way. Only ever moves a window
  // that is on a normal workspace, so a user who dragged it somewhere on
  // purpose is left alone after that first time.
  property bool parkedOnce: false
  // A named Hyprland rule that maps the app window straight onto
  // special:ytm, silent, unfocused and without animation, so a launch no
  // longer flashes it on screen before the move below (Solfa does the same
  // with a permanent rule). Here it is only enabled around a launch and
  // switched off once the window is up (or after a minute): a permanent rule
  // would also hide a YouTube Music web app installed in the user's own
  // browser, whose window class is the same. The plain sign-in window is a
  // normal browser window and never matches. Kept in a Lua global so
  // repeated launches reuse one rule.
  readonly property string ruleClass: "^[a-z-]+-music\\.youtube\\.com__-Default$"
  function holdNextWindow(on) {
    if (!root.setting("parkWindow", true)) return
    var lua = on
      ? "local r = _G.__tiertek_ytm_rule; if r then r:set_enabled(true) else _G.__tiertek_ytm_rule = hl.window_rule({ "
        + "name = [[tiertek-ytm]], match = { class = [[" + root.ruleClass + "]] }, workspace = [[special:ytm silent]], "
        + "no_initial_focus = true, no_anim = true, focus_on_activate = false, suppress_event = [[activate activatefocus]] }) end"
      : "local r = _G.__tiertek_ytm_rule; if r then r:set_enabled(false) end"
    Quickshell.execDetached(["hyprctl", "eval", lua])
    if (on) ruleTimeout.restart()
    else ruleTimeout.stop()
  }
  Timer { id: ruleTimeout; interval: 60000; repeat: false; onTriggered: root.holdNextWindow(false) }

  onAppWindowChanged: {
    if (!root.appWindow) { root.parkedOnce = false; return }
    if (ruleTimeout.running) root.holdNextWindow(false)
    if (root.parkedOnce || !root.setting("parkWindow", true)) return
    var ws = root.appWindow.lastIpcObject && root.appWindow.lastIpcObject.workspace ? root.appWindow.lastIpcObject.workspace : {}
    if (String(ws.name || "").indexOf("special:") === 0) { root.parkedOnce = true; return }
    root.parkedOnce = true
    root.dispatch("hl.dsp.window.move({ window = " + root.windowSelector() + ", workspace = [[special:ytm]], follow = false })")
  }
}
