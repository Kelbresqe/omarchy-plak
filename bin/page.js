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
      return { loggedIn: !!cfg("LOGGED_IN"), video: currentVideo() }
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
      location.assign(watchUrl(arg.video || "", list))
      return { navigated: true }
    },

    async radio(arg) {
      location.assign(watchUrl(arg.video, "RDAMVM" + arg.video))
      return { navigated: true }
    },

    // Click the player bar's shuffle button unless it is already on. Used by
    // the bridge after a `play` with shuffle:true, once the page is back.
    async "player.shuffle"() {
      const bar = playerBar()
      const btn = bar && bar.querySelector("tp-yt-paper-icon-button.shuffle, .shuffle")
      if (!btn) return { shuffled: false }
      if (btn.getAttribute("aria-pressed") === "true") return { shuffled: true }
      btn.click()
      return { shuffled: true }
    },

    async queue() {
      const dom = domQueue()
      if (dom) return { source: "dom", items: dom }
      const v = currentVideo()
      if (!v) return { source: "none", items: [] }
      const next = await innertube("next", { videoId: v, enablePersistentPlaylistPanel: true, isAudioOnly: true })
      return { source: "next", next: next }
    },

    async "queue.jump"(arg) {
      const items = Array.from(document.querySelectorAll("ytmusic-player-queue-item"))
      const el = items[arg.index]
      if (!el) return { jumped: false }
      const btn = el.querySelector("ytmusic-play-button-renderer") || el
      btn.click()
      return { jumped: true }
    },

    async like(arg) { return innertube("like/like", { target: { videoId: arg.video } }) },
    async dislike(arg) { return innertube("like/dislike", { target: { videoId: arg.video } }) },
    async unlike(arg) { return innertube("like/removelike", { target: { videoId: arg.video } }) },

    async "playlist.add"(arg) {
      let list = arg.list
      if (list.startsWith("VL")) list = list.slice(2)
      return innertube("browse/edit_playlist", {
        playlistId: list, actions: [{ action: "ACTION_ADD_VIDEO", addedVideoId: arg.video }],
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
  }

  window.__ytm = async function (op, arg) {
    const fn = Object.prototype.hasOwnProperty.call(ops, op) ? ops[op] : null
    if (!fn) throw new Error("unknown-op")
    return fn(arg || {})
  }
})()
