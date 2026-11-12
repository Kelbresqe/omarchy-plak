// Pure helpers shared by the QML and the tests: the id grammar and the
// InnerTube → flat model parsers. No Qt imports, so node can run it.
//
// Same grammar as VALID_ID in bin/ytm-bridge; tests/test-id-grammar.sh keeps
// the two identical. Ids never reach a shell — the bridge puts them in JSON
// and the page puts them in URLSearchParams — so the grammar exists to keep
// the *page* honest, not to escape anything.
var ID_RE = /^[A-Za-z0-9_-]{2,64}$/

function isValidId(s) {
  return typeof s === "string" && ID_RE.test(s)
}

// node needs module.exports; QML ignores it.
if (typeof module !== "undefined") module.exports = { isValidId: isValidId }

// ------------------------------------------------------------ InnerTube walk

// Every object at any depth that has property `key`, in document order.
// YouTube moves renderers between wrapper layouts every few months; the
// renderers themselves are far more stable than the path to them.
function collect(node, key, out, depth) {
  out = out || []
  depth = depth || 0
  if (!node || typeof node !== "object" || depth > 40) return out
  if (Array.isArray(node)) {
    for (var i = 0; i < node.length; i++) collect(node[i], key, out, depth + 1)
    return out
  }
  if (Object.prototype.hasOwnProperty.call(node, key)) out.push(node[key])
  for (var k in node) {
    if (k !== key) collect(node[k], key, out, depth + 1)
  }
  return out
}

function runsText(obj) {
  if (!obj) return ""
  if (typeof obj === "string") return obj
  if (obj.simpleText) return String(obj.simpleText)
  var runs = obj.runs
  if (!Array.isArray(runs)) return ""
  var s = ""
  for (var i = 0; i < runs.length; i++) s += runs[i] && runs[i].text ? runs[i].text : ""
  return s
}

// Runs are joined with " • " by YouTube; the artist is the run(s) before the
// first separator, the album the one after.
function splitRuns(obj) {
  var parts = [], cur = ""
  var runs = obj && Array.isArray(obj.runs) ? obj.runs : []
  for (var i = 0; i < runs.length; i++) {
    var t = runs[i] && runs[i].text ? String(runs[i].text) : ""
    if (t.trim() === "•") { parts.push(cur.trim()); cur = "" } else cur += t
  }
  if (cur.trim() !== "" || parts.length === 0) parts.push(cur.trim())
  return parts
}

// The shell loads thumbnails itself, so a URL from page data is only used
// when it points at Google's image hosts; anything else would make the
// shell fetch from wherever the data says.
var THUMB_HOST = /^https:\/\/([a-z0-9-]+\.)*(googleusercontent\.com|ytimg\.com|ggpht\.com|gstatic\.com)\//

// Smallest allowed thumbnail that is at least `min` px wide, else the largest.
function pickThumb(thumbnails, min) {
  if (!Array.isArray(thumbnails)) return ""
  min = min || 120
  var ok = thumbnails.filter(function(t) { return t && THUMB_HOST.test(String(t.url || "")) })
  if (ok.length === 0) return ""
  var best = null
  for (var i = 0; i < ok.length; i++) {
    var t = ok[i]
    if ((t.width || 0) >= min && (!best || (t.width || 0) < (best.width || 0))) best = t
  }
  if (!best) best = ok[ok.length - 1]
  return String(best.url)
}

function thumbOf(renderer) {
  var lists = collect(renderer, "thumbnails")
  return lists.length ? pickThumb(lists[0]) : ""
}

function firstBrowseId(node) {
  var ids = collect(node, "browseId")
  return ids.length ? String(ids[0]) : ""
}

function firstVideoId(node) {
  var ids = collect(node, "videoId")
  for (var i = 0; i < ids.length; i++) if (isValidId(ids[i])) return String(ids[i])
  return ""
}

function likeStatusOf(renderer) {
  var s = collect(renderer, "likeStatus")
  return s.length ? String(s[0]) : ""
}

function parseCount(text) {
  var m = String(text || "").match(/(\d[\d,.]*)\s*(songs?|tracks?|videos?|episodes?)/i)
  return m ? parseInt(m[1].replace(/[,.]/g, ""), 10) : 0
}

// browse FEmusic_liked_playlists → [{id,title,count,thumb,author}]
function parsePlaylists(json) {
  var out = []
  var items = collect(json, "musicTwoRowItemRenderer")
  for (var i = 0; i < items.length; i++) {
    var r = items[i]
    var id = firstBrowseId(r.title && r.title.runs && r.title.runs[0] ? r.title.runs[0] : r)
    if (!id) id = firstBrowseId(r.navigationEndpoint || {})
    if (!isValidId(id)) continue           // "New playlist" tile has none
    if (id.indexOf("VL") === 0) id = id.slice(2)
    var sub = splitRuns(r.subtitle)
    var author = "", count = 0
    for (var j = 0; j < sub.length; j++) {
      if (/song|track|video|episode/i.test(sub[j])) count = parseCount(sub[j])
      else if (!/^(auto )?playlist$/i.test(sub[j]) && sub[j] !== "") author = sub[j]
    }
    out.push({ id: id, title: runsText(r.title), count: count, thumb: thumbOf(r), author: author })
  }
  return out
}

// "Song", "Video", "Album", ... as YouTube labels search rows; "" otherwise.
function kindLabel(text) {
  var m = String(text || "").trim().match(/^(song|video|album|playlist|artist|episode|podcast|profile|single|ep)$/i)
  return m ? m[1].toLowerCase() : ""
}

// One musicResponsiveListItemRenderer → track row, or null.
function parseListItem(r) {
  var cols = collect(r, "musicResponsiveListItemFlexColumnRenderer")
  var title = cols[0] ? runsText(cols[0].text) : ""
  var videoId = ""
  if (r.playlistItemData && isValidId(r.playlistItemData.videoId)) videoId = r.playlistItemData.videoId
  if (!videoId && cols[0]) videoId = firstVideoId(cols[0])
  if (!videoId) videoId = firstVideoId(r.overlay || {})
  if (!videoId || !title) return null
  var by = cols[1] ? splitRuns(cols[1].text) : [""]
  var kind = kindLabel(by[0])
  if (kind) by.shift()                    // search rows lead with "Song"/"Video"
  var artist = by[0] || ""
  var album = cols[2] ? runsText(cols[2].text) : ""
  if (kind && !album) album = by[1] || ""
  if (kind === "video" && /views?$/i.test(album)) album = ""
  var fixed = collect(r, "musicResponsiveListItemFixedColumnRenderer")
  var dur = fixed[0] ? runsText(fixed[0].text) : ""
  if (!dur && kind) {
    for (var d = 1; d < by.length; d++) if (/^\d+:\d\d(:\d\d)?$/.test(by[d])) dur = by[d]
  }
  var like = likeStatusOf(r)
  return { videoId: videoId, title: title, artist: artist, album: album, dur: dur,
           thumb: thumbOf(r), liked: like === "LIKE" }
}

// browse VL<playlist> (or MPREb album) → {playlistId, title, items}
function parsePlaylistItems(json) {
  var items = []
  var pages = json && Array.isArray(json.pages) ? json.pages : [json]
  var rows = []
  for (var p = 0; p < pages.length; p++) rows = rows.concat(collect(pages[p], "musicResponsiveListItemRenderer"))
  for (var i = 0; i < rows.length; i++) {
    var row = parseListItem(rows[i])
    if (row) items.push(row)
  }
  json = pages[0]
  var playlistId = ""
  var canon = collect(json, "urlCanonical")
  if (canon.length) {
    var m = String(canon[0]).match(/[?&]list=([A-Za-z0-9_-]{2,64})/)
    if (m) playlistId = m[1]
  }
  var headers = collect(json, "musicResponsiveHeaderRenderer").concat(collect(json, "musicDetailHeaderRenderer"),
    collect(json, "musicEditablePlaylistDetailHeaderRenderer"))
  var title = ""
  for (var h = 0; h < headers.length && !title; h++) title = runsText(headers[h].title)
  return { playlistId: playlistId, title: title, items: items }
}

// One playlistPanelVideoRenderer → queue row.
function parseQueueItem(r, selected) {
  if (!r || !isValidId(r.videoId)) return null
  var by = splitRuns(r.longBylineText || r.shortBylineText)
  return { videoId: r.videoId, title: runsText(r.title), artist: by[0] || "", album: by[1] || "",
           dur: runsText(r.lengthText), thumb: thumbOf(r), selected: !!(selected || r.selected) }
}

// page `queue` result ({source:"store"|"dom", items} | {source:"next", next})
// → {items, current}. "store" rows come from the site's queue store with
// their store index and an exact selection. For "dom" rows `currentVideo`,
// when known, wins over the `selected` flag, which lingers on a skipped
// track's video twin. Every row keeps `index`, the position the bridge's
// queue ops take: rows that fail to parse are skipped, so the list
// position alone would drift.
function parseQueue(data, currentVideo) {
  var items = [], current = -1
  if (!data) return { items: items, current: current }
  var raw = []
  var exact = data.source === "store"
  if ((data.source === "dom" || exact) && Array.isArray(data.items)) {
    for (var i = 0; i < data.items.length; i++) {
      var e = data.items[i] || {}
      var r = e.playlistPanelVideoRenderer
      // Wrapped variants carry the renderer one level down.
      if (r && r.playlistPanelVideoWrapperRenderer) r = collect(r, "playlistPanelVideoRenderer")[0]
      raw.push({ r: r, selected: e.selected, index: typeof e.index === "number" ? e.index : i })
    }
  } else if (data.source === "next") {
    var rs = collect(data.next, "playlistPanelVideoRenderer")
    for (var j = 0; j < rs.length; j++) raw.push({ r: rs[j], selected: false, index: j })
  }
  var lastSelected = -1
  for (var k = 0; k < raw.length; k++) {
    var row = parseQueueItem(raw[k].r, raw[k].selected)
    if (!row) continue
    row.index = raw[k].index
    if (exact) {
      if (raw[k].selected && current < 0) current = items.length
    } else {
      if (currentVideo && row.videoId === currentVideo && current < 0) current = items.length
      if (row.selected) lastSelected = items.length
    }
    items.push(row)
  }
  if (current < 0 && !exact) current = lastSelected
  for (var m = 0; m < items.length; m++) items[m].selected = m === current
  return { items: items, current: current }
}

// page `lyrics` result → {timed:[{t,line}]|null, plain|null, source}
function parseLyrics(data) {
  var out = { timed: null, plain: null, source: "" }
  if (!data) return out
  var timedLists = collect(data.timedRaw, "timedLyricsData")
  if (timedLists.length && Array.isArray(timedLists[0]) && timedLists[0].length) {
    var lines = []
    for (var i = 0; i < timedLists[0].length; i++) {
      var l = timedLists[0][i] || {}
      var t = l.cueRange ? parseInt(l.cueRange.startTimeMilliseconds, 10) : NaN
      if (isNaN(t)) continue
      lines.push({ t: t, line: String(l.lyricLine || "") })
    }
    if (lines.length) out.timed = lines
    var src = collect(data.timedRaw, "sourceMessage")
    if (src.length) out.source = String(src[0])
  }
  var shelves = collect(data.plainRaw, "musicDescriptionShelfRenderer")
  if (shelves.length) {
    var text = runsText(shelves[0].description)
    if (text) out.plain = text
    if (!out.source) out.source = runsText(shelves[0].footer)
  }
  return out
}

// browse FEmusic_home (one page or {pages}) → [{title, items}] where each
// item is {kind:"song"|"list"|"album", videoId, list, title, subtitle, thumb, wide}.
// Songs carry their radio playlist so playing one starts a station like the
// site does; lists are playlists and mixes (VL… stripped); albums keep their
// MPREb browse id and are resolved to a playlist when played.
function parseHome(json) {
  var pages = json && Array.isArray(json.pages) ? json.pages : [json]
  var shelves = []
  for (var p = 0; p < pages.length; p++) {
    var carousels = collect(pages[p], "musicCarouselShelfRenderer")
    for (var c = 0; c < carousels.length; c++) {
      var sh = carousels[c]
      var titleRuns = collect(sh.header || {}, "title")
      var title = titleRuns.length ? runsText(titleRuns[0]) : ""
      var items = []
      var tiles = collect(sh.contents || [], "musicTwoRowItemRenderer")
      for (var i = 0; i < tiles.length; i++) {
        var item = parseHomeTile(tiles[i])
        if (item) items.push(item)
      }
      if (items.length) shelves.push({ title: title, items: items })
    }
  }
  return shelves
}

function parseHomeTile(r) {
  var ep = r.navigationEndpoint || {}
  var item = { kind: "", videoId: "", list: "", title: runsText(r.title), subtitle: splitRuns(r.subtitle).join("  ·  "),
               thumb: thumbOf(r), wide: String(r.aspectRatio || "").indexOf("16_9") !== -1 }
  if (ep.watchEndpoint && isValidId(ep.watchEndpoint.videoId)) {
    item.kind = "song"
    item.videoId = ep.watchEndpoint.videoId
    if (isValidId(ep.watchEndpoint.playlistId)) item.list = ep.watchEndpoint.playlistId
  } else if (ep.watchPlaylistEndpoint && isValidId(ep.watchPlaylistEndpoint.playlistId)) {
    item.kind = "list"
    item.list = ep.watchPlaylistEndpoint.playlistId
  } else if (ep.browseEndpoint && isValidId(ep.browseEndpoint.browseId)) {
    var id = ep.browseEndpoint.browseId
    if (id.indexOf("MPREb") === 0) { item.kind = "album"; item.list = id }
    else if (id.indexOf("VL") === 0) { item.kind = "list"; item.list = id.slice(2) }
    else return null                       // artist / channel pages: not playable here
  } else return null
  if (!item.title) return null
  return item
}

// search → {songs, albums, playlists}; songs are track rows, albums and
// playlists are {id,title,subtitle,thumb} with id a browseId.
//
// Two layouts exist: shelves titled "Songs"/"Albums"/… (older), and a flat
// list where every row labels itself in its second column ("Song • Artist").
// Rows are classified by their own label first, the shelf title second, and
// the id prefix last.
function parseSearch(json) {
  var out = { songs: [], albums: [], playlists: [] }
  var seen = {}
  // Top-result card: a song or video with a watch endpoint.
  var cards = collect(json, "musicCardShelfRenderer")
  for (var c = 0; c < cards.length; c++) {
    var card = cards[c]
    var sub = splitRuns(card.subtitle)
    var ck = kindLabel(sub[0])
    var cv = firstVideoId(card.onTap || card.title || {})
    if ((ck === "song" || ck === "video") && cv && !seen[cv]) {
      seen[cv] = true
      out.songs.push({ videoId: cv, title: runsText(card.title), artist: sub[1] || "", album: "",
                       dur: sub[2] && /^\d+:\d\d/.test(sub[2]) ? sub[2] : "", thumb: thumbOf(card.thumbnail || card),
                       liked: likeStatusOf(card) === "LIKE" })
    }
  }
  var rows = collect(json, "musicResponsiveListItemRenderer")
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var cols = collect(r, "musicResponsiveListItemFlexColumnRenderer")
    var by = cols[1] ? splitRuns(cols[1].text) : [""]
    var kind = kindLabel(by[0])
    var browse = firstBrowseId(r.navigationEndpoint || {})
    if (!kind) {
      if (r.playlistItemData && r.playlistItemData.videoId) kind = "song"
      else if (browse.indexOf("MPREb") === 0) kind = "album"
      else if (browse.indexOf("VL") === 0 || browse.indexOf("PL") === 0 || browse.indexOf("RD") === 0) kind = "playlist"
    }
    if (kind === "song" || kind === "video") {
      var row = parseListItem(r)
      if (row && !seen[row.videoId]) { seen[row.videoId] = true; out.songs.push(row) }
    } else if (kind === "album" || kind === "single" || kind === "ep" || kind === "playlist") {
      if (!isValidId(browse)) continue
      if (kind !== "playlist") by.shift()
      else by.shift()
      var item = { id: browse, title: cols[0] ? runsText(cols[0].text) : "", subtitle: by.join(" · "), thumb: thumbOf(r) }
      if (kind === "playlist") { if (item.id.indexOf("VL") === 0) item.id = item.id.slice(2); out.playlists.push(item) }
      else out.albums.push(item)
    }
  }
  return out
}

// page `playlist.targets` (playlist/get_add_to_playlist) → [{id, title,
// contains}]: the playlists this account can add the song to, and whether
// each already has it. The picker idea and renderer come from Dqckey's
// omarchy-ytmusic-player (MIT).
function parseSaveTargets(json) {
  var out = []
  var rs = collect(json, "playlistAddToOptionRenderer")
  for (var i = 0; i < rs.length; i++) {
    var r = rs[i]
    var id = String(r.playlistId || "")
    if (id.indexOf("VL") === 0) id = id.slice(2)
    if (!isValidId(id)) continue
    out.push({ id: id, title: runsText(r.title), contains: r.containsSelectedVideos === "ALL" })
  }
  return out
}

// page `history` (browse FEmusic_history) → [{title, items}]: one shelf per
// day ("Today", "Yesterday", …, in the account's language), rows as in a
// playlist. Shelves that end up empty are dropped.
function parseHistory(json) {
  var out = []
  var shelves = collect(json, "musicShelfRenderer")
  for (var i = 0; i < shelves.length; i++) {
    var rows = collect(shelves[i].contents || [], "musicResponsiveListItemRenderer")
    var items = []
    for (var j = 0; j < rows.length; j++) {
      var row = parseListItem(rows[j])
      if (row) items.push(row)
    }
    if (items.length) out.push({ title: runsText(shelves[i].title), items: items })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports.parseSaveTargets = parseSaveTargets
  module.exports.parseHistory = parseHistory
  module.exports.collect = collect
  module.exports.runsText = runsText
  module.exports.splitRuns = splitRuns
  module.exports.pickThumb = pickThumb
  module.exports.parsePlaylists = parsePlaylists
  module.exports.parsePlaylistItems = parsePlaylistItems
  module.exports.parseQueue = parseQueue
  module.exports.parseLyrics = parseLyrics
  module.exports.parseSearch = parseSearch
  module.exports.parseHome = parseHome
}
