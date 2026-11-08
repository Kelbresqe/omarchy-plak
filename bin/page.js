// page.js — the only code the bridge installs into the YouTube Music page.
//
// It is evaluated once per attach (and again after a full navigation) and
// defines window.__ytm(op, arg). Every op runs the site's own InnerTube
// endpoints with the page's own session: cookies go along because the
// request is same-origin, and the SAPISIDHASH header is computed here from
// document.cookie exactly as the site's client does. Nothing here is ever
// read back out except the JSON result of the call.
//
// Ids arrive already validated by the bridge (^[A-Za-z0-9_-]{2,64}$) and are
// only ever placed into JSON bodies or URLSearchParams — never into HTML or
// into a string that is evaluated.
(function () {
  "use strict"

  const ORIGIN = "https://music.youtube.com"

  function cfg(key) {
    try { return window.ytcfg && window.ytcfg.get ? window.ytcfg.get(key) : undefined } catch (e) { return undefined }
  }

  function cookie(name) {
    const m = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]+)"))
    return m ? m[1] : ""
  }

  async function sha1hex(text) {
    const buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text))
    return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("")
  }

  // POST /youtubei/v1/<endpoint> as the signed-in user.
  //
  // `clientOverride` swaps the client identity for a mobile one and sends the
  // request *anonymously* (no cookies, no SAPISIDHASH): the mobile clients
  // reject the web session outright (HTTP 400, measured 2026-09-19), and the
  // one thing we need from them — timed lyrics — needs no account.
  async function innertube(endpoint, body, clientOverride) {
    const base = cfg("INNERTUBE_CONTEXT")
    if (!base) throw new Error("no-innertube-context")
    let ctx = JSON.parse(JSON.stringify(base))
    const headers = { "Content-Type": "application/json" }
    let credentials = "include"
    if (clientOverride) {
      ctx = { client: Object.assign({ hl: ctx.client.hl || "en", gl: ctx.client.gl || "US" }, clientOverride), user: {} }
      credentials = "omit"
    } else {
      const sapisid = cookie("SAPISID") || cookie("__Secure-3PAPISID")
      const ts = Math.floor(Date.now() / 1000)
      headers["X-Origin"] = ORIGIN
      headers["X-Goog-AuthUser"] = String(cfg("SESSION_INDEX") || 0)
      headers["X-Youtube-Client-Name"] = String(cfg("INNERTUBE_CONTEXT_CLIENT_NAME") || 67)
      headers["X-Youtube-Client-Version"] = String(ctx.client.clientVersion || "")
      if (sapisid) headers["Authorization"] = "SAPISIDHASH " + ts + "_" + (await sha1hex(ts + " " + sapisid + " " + ORIGIN))
    }
    const r = await fetch("/youtubei/v1/" + endpoint + "?prettyPrint=false", {
      method: "POST",
      credentials: credentials,
      headers: headers,
      body: JSON.stringify(Object.assign({ context: ctx }, body || {})),
    })
    if (!r.ok) {
      let detail = ""
      try { detail = (await r.text()).slice(0, 200) } catch (e) { /* ignore */ }
      throw new Error("http-" + r.status + " " + detail)
    }
    return r.json()
  }

  function watchUrl(video, list) {
    const p = new URLSearchParams()
    if (video) p.set("v", video)
    if (list) p.set("list", list)
    return ORIGIN + "/watch?" + p.toString()
  }

  function currentList() {
    const ok = v => typeof v === "string" && /^[A-Za-z0-9_-]{2,64}$/.test(v)
    try {
      const mp = document.getElementById("movie_player")
      const pl = mp && typeof mp.getPlaylistId === "function" ? mp.getPlaylistId() : ""
      if (ok(pl)) return pl
    } catch (e) { /* player not up yet */ }
    const l = new URLSearchParams(location.search).get("list")
    return ok(l) ? l : ""
  }

  // Start playback in place, the way the site's own links do: a yt-navigate
  // event carrying a watch endpoint, fired at <ytmusic-app>. Loading the URL
  // instead reloads the page, and while something plays the site answers that
  // with a "Leave site?" prompt that pops the window up and blocks until it
  // is confirmed. If the app does not pick the navigation up within a few
  // seconds (the site changed), fall back to loading the URL; the bridge
  // confirms that prompt itself. Resolves to {navigated, reloaded}.
  async function watch(video, list) {
    const app = document.querySelector("ytmusic-app")
    const before = currentVideo()
    if (app) {
      const we = {}
      const p = new URLSearchParams()
      if (video) { we.videoId = video; p.set("v", video) }
      if (list) { we.playlistId = list; p.set("list", list) }
      app.dispatchEvent(new CustomEvent("yt-navigate", { bubbles: true, composed: true, detail: { endpoint: {
        commandMetadata: { webCommandMetadata: { url: "/watch?" + p.toString(), webPageType: "WEB_PAGE_TYPE_WATCH", rootVe: 3832 } },
        watchEndpoint: we,
      } } }))
      // Taken once the requested track is loaded; for a bare list, once that
      // list is loaded with a different track than before.
      for (let i = 0; i < 40; i++) {
        const v = currentVideo()
        if (video ? v === video : (currentList() === list && v !== "" && v !== before)) return { navigated: true, reloaded: false }
        await new Promise(r => setTimeout(r, 100))
      }
    }
    location.assign(watchUrl(video, list))
    return { navigated: true, reloaded: true }
  }

  // The playing track. The HTML5 player knows best; the queue's `selected`
  // flag lingers on the previous track's video twin after a skip, and the
  // URL is only /watch?v=… right after a navigation.
  function currentVideo() {
    const ok = v => typeof v === "string" && /^[A-Za-z0-9_-]{2,64}$/.test(v)
    try {
      const mp = document.getElementById("movie_player")
      const data = mp && typeof mp.getVideoData === "function" ? mp.getVideoData() : null
      if (data && ok(data.video_id)) return data.video_id
    } catch (e) { /* player not up yet */ }
    let last = ""
    for (const el of document.querySelectorAll("ytmusic-player-queue-item")) {
      if ((el.hasAttribute("selected") || (el.data && el.data.selected === true)) && el.data && ok(el.data.videoId)) last = el.data.videoId
    }
    if (last) return last
    const v = new URLSearchParams(location.search).get("v")
    return ok(v) ? v : ""
  }

  function playerBar() { return document.querySelector("ytmusic-player-bar") }

  // The player bar's own volume slider (0–100). Driving it rather than
  // movie_player.setVolume() keeps the site's loudness curve, keeps its UI in
  // step, and is what the site remembers across reloads (the `volume` field
  // of its PREF cookie); setVolume() alone is forgotten on the next track.
  function volumeSlider() {
    const bar = playerBar()
    return bar ? bar.querySelector("#volume-slider") : null
  }

  // Repeat lives on the player bar as `repeatMode` (NONE / ALL / ONE) and is
  // changed by its repeat button, which cycles NONE → ALL → ONE. Chromium's
  // MPRIS player has no LoopStatus, so this is the only way in. The bar holds
  // two .repeat buttons; the visible one is in .right-controls-buttons.
  const REPEAT_MODES = ["NONE", "ALL", "ONE"]
  function repeatMode() {
    const bar = playerBar()
    const m = bar ? String(bar.repeatMode || bar.getAttribute("repeat-mode") || "") : ""
    return REPEAT_MODES.includes(m) ? m : null
  }
  function repeatButton() {
    const bar = playerBar()
    return bar ? bar.querySelector(".right-controls-buttons .repeat") || bar.querySelector(".repeat") : null
  }

  // Shuffle is a toggle on current YouTube Music: the player bar's boolean
  // `shuffleOn` flips with each click of its shuffle button (turning it off
  // keeps the shuffled order). The button has no aria-pressed. Chromium's
  // MPRIS player has no Shuffle property.
  function shuffleOn() {
    const bar = playerBar()
    return bar && typeof bar.shuffleOn === "boolean" ? bar.shuffleOn : null
  }
  function shuffleButton() {
    const bar = playerBar()
    return bar ? bar.querySelector(".right-controls-buttons .shuffle") || bar.querySelector(".shuffle") : null
  }

  // What the bridge remembers between browser sessions (Memory in
  // ytm-bridge): the list the track came from, how far in, its title for the
  // Resume button, and the settings the site forgets when its browser
  // restarts (repeat, shuffle) or that the panel shows before the page
  // answers (volume). Every field is optional; the bridge validates them.
  function sessionInfo() {
    const ok = v => typeof v === "string" && /^[A-Za-z0-9_-]{2,64}$/.test(v)
    const out = { list: "", time: 0, title: "", artist: "", repeat: repeatMode(), shuffle: shuffleOn(), volume: null }
    try {
      const mp = document.getElementById("movie_player")
      if (mp && typeof mp.getCurrentTime === "function") out.time = Math.max(0, Math.floor(Number(mp.getCurrentTime()) || 0))
      const pl = mp && typeof mp.getPlaylistId === "function" ? mp.getPlaylistId() : ""
      if (ok(pl)) out.list = pl
      const data = mp && typeof mp.getVideoData === "function" ? mp.getVideoData() : null
      if (data) {
        out.title = String(data.title || "").slice(0, 200)
        out.artist = String(data.author || "").slice(0, 200)
      }
    } catch (e) { /* player not up yet */ }
    if (!out.list) {
      const l = new URLSearchParams(location.search).get("list")
      if (ok(l)) out.list = l
    }
    const s = volumeSlider()
    if (s) out.volume = Number(s.value)
    return out
  }

  // The site's own queue store (Redux-style getState / dispatch on
  // <ytmusic-app>.queue). Reading and editing the queue through it keeps
  // indexes exact: the rendered rows also hold stale and twin entries
  // (measured: 58 rows for a 50-item queue). Store access and the action
  // names (ADD_ITEMS, REMOVE_ITEM, MOVE_ITEM, SET_INDEX) follow Solfa,
  // SirAllap/omarchy-solfa (MIT).
  function queueStore() {
    const a = document.querySelector("ytmusic-app")
    const s = a && a.queue && a.queue.store
    return s && typeof s.getState === "function" && typeof s.dispatch === "function" ? s : null
  }

  function storeRenderer(item) {
    if (!item) return null
    if (item.playlistPanelVideoRenderer) return item.playlistPanelVideoRenderer
    const w = item.playlistPanelVideoWrapperRenderer
    return (w && w.primaryRenderer && w.primaryRenderer.playlistPanelVideoRenderer) || null
  }

  // After an edit the selection index points at whatever now sits there;
  // put it back on the track that is playing.
  function keepSelection(s, videoId) {
    const q = s.getState().queue
    for (let i = 0; i < q.items.length; i++) {
      const r = storeRenderer(q.items[i])
      if (r && r.videoId === videoId) {
        if (i !== q.selectedItemIndex) s.dispatch({ type: "SET_INDEX", payload: i })
        return
      }
    }
  }

  function needStore() {
    const s = queueStore()
    if (!s) throw new Error("no-queue")
    return s
  }

  // Polymer elements expose their renderer JSON as `.data`; the queue items
  // carry the same playlistPanelVideoRenderer shape the `next` endpoint uses,
  // so the parser in Ytm.js handles both without knowing which one it got.
  function domQueue() {
    const items = Array.from(document.querySelectorAll("ytmusic-player-queue-item"))
    if (items.length === 0) return null
    return items.map(el => ({
      playlistPanelVideoRenderer: el.data || null,
      selected: el.hasAttribute("selected") || (el.data && el.data.selected === true),
    }))
  }

  // First continuation token in a browse response, either shape.
  function continuationToken(json) {
    const found = []
    ;(function walk(node, depth) {
      if (!node || typeof node !== "object" || depth > 40 || found.length) return
      if (node.continuationCommand && node.continuationCommand.token) { found.push(node.continuationCommand.token); return }
      if (node.nextContinuationData && node.nextContinuationData.continuation) { found.push(node.nextContinuationData.continuation); return }
      for (const k in node) walk(node[k], depth + 1)
    })(json, 0)
    return found[0] || ""
  }

  function findLyricsTab(nextJson) {
    // The lyrics tab is the second tab of the watch-next tabbed renderer.
    try {
      const tabs = nextJson.contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer
        .watchNextTabbedResultsRenderer.tabs
      for (const t of tabs) {
        const tr = t.tabRenderer
        const id = tr && tr.endpoint && tr.endpoint.browseEndpoint && tr.endpoint.browseEndpoint.browseId
        if (id && id.startsWith("MPLYt")) return { browseId: id, unselectable: !!tr.unselectable }
      }
    } catch (e) { /* shape changed */ }
    return null
  }

  const ops = {
    async state() {
      return { loggedIn: !!cfg("LOGGED_IN"), video: currentVideo(), session: sessionInfo() }
    },

    // Seek once the requested track is the one loaded (Resume navigates
    // first); `seeked` is false while another track is still up.
    async "player.seek"(arg) {
      const mp = document.getElementById("movie_player")
      if (!mp || typeof mp.seekTo !== "function" || currentVideo() !== arg.video) return { seeked: false }
      mp.seekTo(arg.t, true)
      return { seeked: true }
    },

    async now() {
      const bar = playerBar()
      const title = bar ? (bar.querySelector(".title") || {}).textContent || "" : ""
      let liked = null
      const like = bar && bar.querySelector("ytmusic-like-button-renderer")
      if (like && like.data && like.data.likeStatus) liked = like.data.likeStatus
      return { video: currentVideo(), title: title.trim(), liked: liked }
    },

    // The home page arrives in slices; Quick picks and the mixes are usually
    // in the second or third. Three pages is what the site itself loads.
    async home() {
      const pages = [await innertube("browse", { browseId: "FEmusic_home" })]
      for (let n = 0; n < 2; n++) {
        const token = continuationToken(pages[pages.length - 1])
        if (!token) break
        pages.push(await innertube("browse", { continuation: token }))
      }
      return { pages: pages }
    },

    async "library.playlists"() {
      return innertube("browse", { browseId: "FEmusic_liked_playlists" })
    },

    // Follows continuations so long playlists come back whole (capped, so a
    // 5 000-track playlist cannot pin the page).
    async "playlist.items"(arg) {
      let id = arg.list
      if (!id.startsWith("VL") && !id.startsWith("MPREb")) id = "VL" + id
      const pages = [await innertube("browse", { browseId: id })]
      for (let n = 0; n < 9; n++) {
        const token = continuationToken(pages[pages.length - 1])
        if (!token) break
        pages.push(await innertube("browse", { continuation: token }))
      }
      return { pages: pages }
    },

    async play(arg) {
      let list = arg.list || ""
      if (list.startsWith("VL")) list = list.slice(2)
      return watch(arg.video || "", list)
    },

    async radio(arg) {
      return watch(arg.video, "RDAMVM" + arg.video)
    },

    // Click the player bar's shuffle button unless it is already on. Used by
    // the bridge after a `play` with shuffle:true, once the page is back.
    // Shuffle is a toggle, so check `shuffleOn` first: clicking while it is
    // already on would turn it off. aria-pressed is only a fallback for a bar
    // without the property.
    async "player.shuffle"() {
      const on = shuffleOn()
      if (on === true) return { shuffled: true }
      const btn = shuffleButton()
      if (!btn) return { shuffled: false }
      if (on === null && btn.getAttribute("aria-pressed") === "true") return { shuffled: true }
      btn.click()
      return { shuffled: true }
    },

    // The store first (exact indexes, see queueStore), then the rendered
    // rows, then the `next` endpoint.
    async queue() {
      const s = queueStore()
      if (s) {
        const q = s.getState().queue || {}
        const items = (q.items || []).map((it, i) => ({
          playlistPanelVideoRenderer: storeRenderer(it), selected: i === q.selectedItemIndex, index: i,
        }))
        if (items.length) return { source: "store", items: items }
      }
      const dom = domQueue()
      if (dom) return { source: "dom", items: dom }
      const v = currentVideo()
      if (!v) return { source: "none", items: [] }
      const next = await innertube("next", { videoId: v, enablePersistentPlaylistPanel: true, isAudioOnly: true })
      return { source: "next", next: next }
    },

    async "queue.jump"(arg) {
      const s = queueStore()
      const app = document.querySelector("ytmusic-app")
      if (s && app && app.queue && typeof app.queue.selectQueueItem === "function") {
        const entry = (s.getState().queue.items || [])[arg.index]
        if (!entry) return { jumped: false }
        app.queue.selectQueueItem(entry)
        return { jumped: true }
      }
      const items = Array.from(document.querySelectorAll("ytmusic-player-queue-item"))
      const el = items[arg.index]
      if (!el) return { jumped: false }
      const btn = el.querySelector("ytmusic-play-button-renderer") || el
      btn.click()
      return { jumped: true }
    },

    // Put a song right after the playing one (next: true) or at the end.
    // With nothing loaded there is no queue to add to, so it just plays.
    async "queue.add"(arg) {
      const s = queueStore()
      const playing = currentVideo()
      if (!s || !playing || !(s.getState().queue.items || []).length) {
        return Object.assign({ added: 0, played: true }, await watch(arg.video, ""))
      }
      const res = await innertube("music/get_queue", { videoIds: [arg.video] })
      const entries = ((res && res.queueDatas) || []).map(d => d && d.content).filter(Boolean)
      if (!entries.length) throw new Error("not-found")
      const q = s.getState().queue
      const before = q.items.length
      const index = arg.next ? Math.min(before, (q.selectedItemIndex || 0) + 1) : before
      s.dispatch({ type: "ADD_ITEMS", payload: { items: entries, index: index, nextQueueItemId: q.nextQueueItemId, shouldAssignIds: true } })
      keepSelection(s, playing)
      if (s.getState().queue.items.length !== before + entries.length) throw new Error("unchanged")
      return { added: entries.length, index: index }
    },

    async "queue.remove"(arg) {
      const s = needStore()
      const q = s.getState().queue
      if (arg.index < 0 || arg.index >= q.items.length) throw new Error("out-of-range")
      if (arg.index === q.selectedItemIndex) throw new Error("playing")
      const playing = currentVideo()
      s.dispatch({ type: "REMOVE_ITEM", payload: arg.index })
      keepSelection(s, playing)
      return { removed: true }
    },

    async "queue.move"(arg) {
      const s = needStore()
      const n = s.getState().queue.items.length
      if (arg.from < 0 || arg.from >= n || arg.to < 0 || arg.to >= n) throw new Error("out-of-range")
      if (arg.from === arg.to) return { moved: false }
      const playing = currentVideo()
      s.dispatch({ type: "MOVE_ITEM", payload: { fromIndex: arg.from, toIndex: arg.to } })
      keepSelection(s, playing)
      return { moved: true }
    },

    async history() {
      return innertube("browse", { browseId: "FEmusic_history" })
    },

    // The playlists this account can add the song to, with whether each
    // already has it (playlistAddToOptionRenderer.containsSelectedVideos).
    async "playlist.targets"(arg) {
      return innertube("playlist/get_add_to_playlist", { videoIds: [arg.video] })
    },

    // Lower the player's own volume to 0 over `seconds`, pause, then put the
    // volume back. movie_player.setVolume() is not what the site remembers
    // (the slider / PREF cookie are), so nothing is left changed.
    async "player.fade"(arg) {
      const mp = document.getElementById("movie_player")
      if (!mp || typeof mp.setVolume !== "function") return { faded: false }
      const start = mp.getVolume()
      const steps = 20
      const ms = Math.floor(arg.seconds * 1000 / steps)
      for (let i = 1; i <= steps; i++) {
        mp.setVolume(Math.round(start * (1 - i / steps)))
        await new Promise(r => setTimeout(r, ms))
      }
      mp.pauseVideo()
      await new Promise(r => setTimeout(r, 300))
      mp.setVolume(start)
      return { faded: true }
    },

    async like(arg) { return innertube("like/like", { target: { videoId: arg.video } }) },
    async dislike(arg) { return innertube("like/dislike", { target: { videoId: arg.video } }) },
    async unlike(arg) { return innertube("like/removelike", { target: { videoId: arg.video } }) },

    async "playlist.add"(arg) {
      let list = arg.list
      if (list.startsWith("VL")) list = list.slice(2)
      // DEDUPE_OPTION_SKIP: adding a song that is already there is a no-op,
      // not a second copy. The caller checks `status` (STATUS_SUCCEEDED).
      return innertube("browse/edit_playlist", {
        playlistId: list, actions: [{ action: "ACTION_ADD_VIDEO", addedVideoId: arg.video, dedupeOption: "DEDUPE_OPTION_SKIP" }],
      })
    },

    async lyrics(arg) {
      const next = await innertube("next", { videoId: arg.video, isAudioOnly: true })
      const tab = findLyricsTab(next)
      if (!tab || tab.unselectable) return { timed: null, plain: null, source: "", reason: "none" }
      let timed = null, timedError = ""
      try {
        // Timed lyrics are only served to the mobile clients.
        timed = await innertube("browse", { browseId: tab.browseId },
          { clientName: "ANDROID_MUSIC", clientVersion: "7.21.50" })
      } catch (e) { timed = null; timedError = String(e && e.message || e) }
      const plain = await innertube("browse", { browseId: tab.browseId })
      return { timedRaw: timed, plainRaw: plain, browseId: tab.browseId, timedError: timedError }
    },

    async search(arg) {
      return innertube("search", { query: arg.q })
    },

    // Volume in slider units, 0–100. Chromium's MPRIS player accepts a Volume
    // write and ignores it (it always reads back 1.0), so this is the only
    // way the shell can change it. `volume` is null while the bar is not up.
    async "volume.get"() {
      const s = volumeSlider()
      return { volume: s ? Number(s.value) : null }
    },

    async "volume.set"(arg) {
      const s = volumeSlider()
      if (!s) return { volume: null }
      s.value = arg.volume
      s.dispatchEvent(new CustomEvent("change", { bubbles: true }))
      return { volume: Number(s.value) }
    },

    // `mode` is null while the bar is not up.
    async "repeat.get"() {
      return { mode: repeatMode() }
    },

    // Click the site's own button until it reaches `arg.mode` (at most two
    // clicks around the cycle), waiting for each click to land. Setting a
    // target instead of "cycle once" keeps a double-click in the shell from
    // skipping a mode.
    async "repeat.set"(arg) {
      for (let n = 0; n < REPEAT_MODES.length; n++) {
        const now = repeatMode()
        if (now === null || now === arg.mode) return { mode: now }
        const btn = repeatButton()
        if (!btn) return { mode: now }
        btn.click()
        for (let t = 0; t < 20 && repeatMode() === now; t++) await new Promise(r => setTimeout(r, 25))
      }
      return { mode: repeatMode() }
    },

    // `on` is null while the bar is not up.
    async "shuffle.get"() {
      return { on: shuffleOn() }
    },

    // Click only if the state differs from `arg.on`, then wait for the flip.
    async "shuffle.set"(arg) {
      const now = shuffleOn()
      if (now === null || now === arg.on) return { on: now }
      const btn = shuffleButton()
      if (!btn) return { on: now }
      btn.click()
      for (let t = 0; t < 40 && shuffleOn() === now; t++) await new Promise(r => setTimeout(r, 25))
      return { on: shuffleOn() }
    },
  }

  window.__ytm = async function (op, arg) {
    const fn = Object.prototype.hasOwnProperty.call(ops, op) ? ops[op] : null
    if (!fn) throw new Error("unknown-op")
    return fn(arg || {})
  }
})()
