import QtQuick
import qs.Ui
import qs.Commons

// Search. The field takes the keyboard while it has focus; Escape or Down
// hands it back to the list.
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: field.activeFocus

  property var results: ({ songs: [], albums: [], playlists: [] })
  property var flat: []          // [{kind:"song"|"album"|"playlist", item}]
  property int cursor: -1
  property bool loading: false
  property string lastQuery: ""

  function focusInput() { field.forceActiveFocus(); field.selectAll() }

  function rebuild() {
    var out = []
    var r = root.results
    for (var i = 0; i < r.songs.length; i++) out.push({ kind: "song", item: r.songs[i] })
    for (var j = 0; j < r.albums.length; j++) out.push({ kind: "album", item: r.albums[j] })
    for (var k = 0; k < r.playlists.length; k++) out.push({ kind: "playlist", item: r.playlists[k] })
    root.flat = out
    root.cursor = out.length > 0 ? 0 : -1
  }

  function run(q) {
    q = String(q || "").trim()
    if (q === "" || q === root.lastQuery) return
    root.lastQuery = q
    root.loading = true
    root.svc.search(q, function(r) {
      root.loading = false
      if (!r) return
      root.results = r
      root.rebuild()
    })
  }

  function move(dx, dy) {
    var n = root.flat.length
    if (n === 0) return
    root.cursor = Math.max(0, Math.min(n - 1, root.cursor + dy))
    list.positionViewAtIndex(root.cursor, ListView.Contain)
  }

  function activate() {
    var e = root.flat[root.cursor]
    if (!e) return
    if (e.kind === "song") root.svc.play("", e.item.videoId, false)
    else root.svc.play(e.item.id, "", false)
  }

  function textKey(t) { }

  Component.onCompleted: Qt.callLater(root.focusInput)

  Column {
    anchors.fill: parent
    spacing: Style.space(6)

    TextField {
      id: field
      width: parent.width
      placeholderText: "Search songs, albums, playlists…"
      font.family: root.family
      onAccepted: { root.run(text); list.forceActiveFocus() }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { list.forceActiveFocus(); event.accepted = true }
        else if (event.key === Qt.Key_Down) { list.forceActiveFocus(); root.move(0, 0); event.accepted = true }
      }
      onTextChanged: debounce.restart()
    }
    Timer { id: debounce; interval: 450; repeat: false; onTriggered: root.run(field.text) }

    Text {
      textFormat: Text.PlainText
      visible: root.loading || (root.lastQuery !== "" && root.flat.length === 0)
      text: root.loading ? "Searching…" : "No results"
      color: Color.foreground; opacity: 0.5
      font.family: root.family; font.pixelSize: Style.font.caption
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - field.height - Style.space(30)
      clip: true
      model: root.flat
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      delegate: TrackRow {
        required property var modelData
        required property int index
        width: list.width
        family: root.family
        track: modelData.kind === "song" ? modelData.item
          : { title: modelData.item.title, artist: (modelData.kind === "album" ? "Album  ·  " : "Playlist  ·  ") + modelData.item.subtitle, thumb: modelData.item.thumb, dur: "" }
        showAlbum: modelData.kind === "song"
        selected: root.cursor === index
        current: modelData.kind === "song" && root.svc && root.svc.video === modelData.item.videoId
        onActivated: { root.cursor = index; root.activate() }
        onSecondary: if (modelData.kind === "song") root.svc.radio(modelData.item.videoId)
      }
    }
  }
}
