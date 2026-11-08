// Ytm.js parsers added with queue editing, save-to-playlist and history.
const assert = require("assert")
const Y = require("../Ytm.js")
let n = 0
const t = (name, fn) => { fn(); n++ }
const row = (id, title) => ({ playlistPanelVideoRenderer: { videoId: id, title: { runs: [{ text: title }] } } })

t("store queue keeps store indexes and the exact selection", () => {
  const data = { source: "store", items: [
    Object.assign(row("aaaaaaaaaaa", "A"), { selected: false, index: 0 }),
    { playlistPanelVideoRenderer: null, selected: false, index: 1 },          // unparseable
    Object.assign(row("ccccccccccc", "C"), { selected: true, index: 2 }),
    Object.assign(row("ddddddddddd", "D"), { selected: false, index: 3 }),
  ] }
  const q = Y.parseQueue(data, "aaaaaaaaaaa")          // currentVideo must not override the store
  assert.deepStrictEqual(q.items.map(r => r.index), [0, 2, 3])
  assert.strictEqual(q.current, 1)
  assert.strictEqual(q.items[1].videoId, "ccccccccccc")
})

t("dom queue still prefers the current video", () => {
  const data = { source: "dom", items: [Object.assign(row("aaaaaaaaaaa", "A"), { selected: true }), row("bbbbbbbbbbb", "B")] }
  const q = Y.parseQueue(data, "bbbbbbbbbbb")
  assert.strictEqual(q.current, 1)
  assert.deepStrictEqual(q.items.map(r => r.index), [0, 1])
})

t("save targets: VL stripped, contains flag, bad ids dropped", () => {
  const json = { contents: [
    { playlistAddToOptionRenderer: { playlistId: "VLPLabcdef12345", title: { runs: [{ text: "Road" }] }, containsSelectedVideos: "ALL" } },
    { playlistAddToOptionRenderer: { playlistId: "PLzzzzzzzzzz", title: { runs: [{ text: "Gym" }] }, containsSelectedVideos: "NONE" } },
    { playlistAddToOptionRenderer: { playlistId: "bad;id", title: { runs: [{ text: "X" }] } } },
  ] }
  assert.deepStrictEqual(Y.parseSaveTargets(json), [
    { id: "PLabcdef12345", title: "Road", contains: true },
    { id: "PLzzzzzzzzzz", title: "Gym", contains: false },
  ])
})

t("history: one shelf per day, empty shelves dropped", () => {
  const item = (id, title, artist) => ({ musicResponsiveListItemRenderer: {
    playlistItemData: { videoId: id },
    flexColumns: [
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: title }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: artist }] } } },
    ] } })
  const json = { contents: [
    { musicShelfRenderer: { title: { runs: [{ text: "Bugün" }] }, contents: [item("aaaaaaaaaaa", "Song A", "Artist A"), item("bbbbbbbbbbb", "Song B", "Artist B")] } },
    { musicShelfRenderer: { title: { runs: [{ text: "Dün" }] }, contents: [] } },
    { musicShelfRenderer: { title: { runs: [{ text: "Geçen hafta" }] }, contents: [item("ccccccccccc", "Song C", "Artist C")] } },
  ] }
  const h = Y.parseHistory(json)
  assert.deepStrictEqual(h.map(s => [s.title, s.items.length]), [["Bugün", 2], ["Geçen hafta", 1]])
  assert.strictEqual(h[0].items[1].artist, "Artist B")
})

console.log("test-ytm-queue: " + n + " passed")
