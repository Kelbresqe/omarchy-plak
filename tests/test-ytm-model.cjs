const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Y = require("../Ytm.js")

const fx = n => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "innertube", n), "utf8"))
let n = 0
function t(name, fn) { n++; try { fn() } catch (e) { console.error("FAIL", name); throw e } }

t("grammar", () => {
  assert.equal(Y.isValidId("dQw4w9WgXcQ"), true)
  assert.equal(Y.isValidId("PL;rm"), false)
  assert.equal(Y.isValidId(null), false)
  assert.equal(Y.isValidId(12345678), false)
})

t("splitRuns", () => {
  assert.deepEqual(Y.splitRuns({ runs: [{ text: "A" }, { text: " & " }, { text: "B" }, { text: " • " }, { text: "X" }] }), ["A & B", "X"])
  assert.deepEqual(Y.splitRuns({ runs: [] }), [""])
  assert.deepEqual(Y.splitRuns(null), [""])
})

t("pickThumb prefers the smallest >= 120", () => {
  const u = (n) => "https://i.ytimg.com/" + n + ".jpg"
  const th = [{ url: u("a"), width: 60 }, { url: u("b"), width: 226 }, { url: u("c"), width: 544 }]
  assert.equal(Y.pickThumb(th), u("b"))
  assert.equal(Y.pickThumb([{ url: u("a"), width: 60 }]), u("a"))
  assert.equal(Y.pickThumb([]), "")
  assert.equal(Y.pickThumb(undefined), "")
})

t("pickThumb only takes Google's image hosts", () => {
  const good = "https://lh3.googleusercontent.com/x=w226"
  assert.equal(Y.pickThumb([{ url: "https://evil.example/t.jpg", width: 226 }, { url: good, width: 544 }]), good)
  for (const bad of ["https://evil.example/t.jpg", "http://i.ytimg.com/t.jpg", "https://i.ytimg.com.evil.example/t.jpg",
                     "https://evilytimg.com/t.jpg", "file:///etc/passwd", "javascript:alert(1)"])
    assert.equal(Y.pickThumb([{ url: bad, width: 226 }]), "", bad)
})

t("parsePlaylists", () => {
  const r = Y.parsePlaylists(fx("playlists.json"))
  assert.equal(r.length, 2, "New playlist tile skipped")
  assert.deepEqual(r[0], { id: "LM", title: "Liked Music", count: 0, thumb: "https://i.ytimg.com/b.jpg", author: "" })
  assert.equal(r[1].id, "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
  assert.equal(r[1].author, "Sam")
  assert.equal(r[1].count, 1204)
})

t("parsePlaylistItems", () => {
  const r = Y.parsePlaylistItems(fx("playlist-items.json"))
  assert.equal(r.playlistId, "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
  assert.equal(r.title, "Road Trip")
  assert.equal(r.items.length, 2, "row without a videoId dropped")
  assert.deepEqual(r.items[0], { videoId: "dQw4w9WgXcQ", title: "Never Gonna Give You Up", artist: "Rick Astley",
    album: "Whenever You Need Somebody", dur: "3:33", thumb: "https://lh3.googleusercontent.com/t1=w120-h120", liked: true })
  assert.equal(r.items[1].artist, "A & B")
  assert.equal(r.items[1].liked, false)
})

t("parseQueue from DOM", () => {
  const r = Y.parseQueue(fx("queue-dom.json"))
  assert.equal(r.items.length, 2)
  assert.equal(r.current, 1)
  assert.equal(r.items[0].album, "Whenever You Need Somebody")
  assert.equal(r.items[0].thumb, "https://i.ytimg.com/q1.jpg")
})

t("parseQueue prefers the known current video over stale selected flags", () => {
  const f = fx("queue-dom.json")
  const r = Y.parseQueue(f, "dQw4w9WgXcQ")
  assert.equal(r.current, 0)
  assert.equal(r.items[0].selected, true)
  assert.equal(r.items[1].selected, false)
  assert.equal(Y.parseQueue(f, "nomatch1234").current, 1, "falls back to the last selected row")
})

t("parseQueue from next", () => {
  const next = { contents: { x: { playlistPanelRenderer: { contents: [
    { playlistPanelVideoRenderer: { videoId: "dQw4w9WgXcQ", title: { runs: [{ text: "T" }] }, selected: true } } ] } } } }
  const r = Y.parseQueue({ source: "next", next })
  assert.equal(r.items.length, 1)
  assert.equal(r.current, 0)
})

t("parseLyrics timed + plain", () => {
  const r = Y.parseLyrics(fx("lyrics.json"))
  assert.deepEqual(r.timed, [{ t: 18500, line: "We're no strangers to love" }, { t: 22100, line: "You know the rules" }])
  assert.equal(r.plain, "We're no strangers to love\nYou know the rules")
  assert.equal(r.source, "Source: Musixmatch")
})

t("parseLyrics plain only", () => {
  const f = fx("lyrics.json"); f.timedRaw = null
  const r = Y.parseLyrics(f)
  assert.equal(r.timed, null)
  assert.equal(r.plain.length > 0, true)
})

t("parseSearch", () => {
  const r = Y.parseSearch(fx("search.json"))
  assert.equal(r.songs.length, 1)
  assert.equal(r.songs[0].videoId, "songone1234")
  assert.equal(r.albums.length, 1)
  assert.equal(r.albums[0].id, "MPREb_album12345")
  assert.equal(r.playlists.length, 1)
  assert.equal(r.playlists[0].id, "PLcommunity1234")
})

t("never throws on junk", () => {
  for (const junk of [null, undefined, {}, [], "x", 5, { contents: [null, 1, "s"] }]) {
    Y.parsePlaylists(junk); Y.parsePlaylistItems(junk); Y.parseQueue(junk); Y.parseLyrics(junk); Y.parseSearch(junk)
  }
})

t("collect is cycle-safe by depth", () => {
  const a = {}; a.self = a
  assert.deepEqual(Y.collect(a, "nothing"), [])
})

console.log("test-ytm-model: " + n + " passed")

// Real-shape regression (captured 2026-09-19, scrubbed): the flat search layout.
t("parseSearch flat layout", () => {
  const r = Y.parseSearch(fx("search-flat.json"))
  assert.equal(r.songs[0].title, "Stone")                  // top card first
  assert.equal(r.songs[0].dur, "5:36")
  assert.equal(r.songs.length >= 3, true)                  // card + Song row + Video row
  const song = r.songs.find(s => s.videoId === "RX_VXoi4Rck")
  assert.equal(song.artist, "Whiskey Myers")
  assert.equal(r.albums.length, 1)
  assert.equal(r.albums[0].id.indexOf("MPREb"), 0)
  assert.match(r.albums[0].subtitle, /^Whiskey Myers · \d{4}$/)
  assert.equal(r.playlists.length, 1)
  assert.equal(r.playlists[0].id.indexOf("VL"), -1)
})

t("parsePlaylistItems accepts pages", () => {
  const one = fx("playlist-items.json")
  const r = Y.parsePlaylistItems({ pages: [one, one] })
  assert.equal(r.items.length, 4)
  assert.equal(r.playlistId, "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
})
console.log("test-ytm-model: regression ok")

t("parseHome", () => {
  const h = Y.parseHome(fx("home.json"))
  assert.deepEqual(h.map(s => s.title), ["Listen again", "Mixed for you"], "empty shelves dropped, both pages read")
  const a = h[0].items
  assert.equal(a.length, 3, "artist tile skipped")
  assert.deepEqual(a[0], { kind: "list", videoId: "", list: "RDTMAK5uy_supermix123", title: "My Supermix", subtitle: "A, B, C", thumb: "https://i.ytimg.com/mix.jpg", wide: false })
  assert.equal(a[1].kind, "song"); assert.equal(a[1].videoId, "ru5afNNSPeU"); assert.equal(a[1].list, "RDAMVMru5afNNSPeU"); assert.equal(a[1].wide, true)
  assert.equal(a[2].kind, "album"); assert.equal(a[2].list, "MPREb_album12345")
  assert.equal(h[1].items[0].kind, "list"); assert.equal(h[1].items[0].list, "RDTMAK5uy_discover123")
  assert.deepEqual(Y.parseHome(null), []); assert.deepEqual(Y.parseHome({}), [])
})
console.log("test-ytm-model: home ok")
