import QtQuick
import qs.Ui
import qs.Commons

// History: what this account played, under the day headers YouTube Music
// gives ("Today", "Last week", …, in the account's language). Enter plays a
// song; e / E / b and the row buttons queue or save it like elsewhere. The
// idea comes from Solfa (SirAllap/omarchy-solfa, MIT).
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  // Shelves flattened into one list: {header} rows and {track} rows.
  readonly property var rows: {
    var out = []
    var shelves = root.svc ? root.svc.history : []
    for (var i = 0; i < shelves.length; i++) {
      out.push({ header: shelves[i].title })
      for (var j = 0; j < shelves[i].items.length; j++) out.push({ track: shelves[i].items[j] })
    }
    return out
  }
  property int cursor: -1

  function tr(key, fallback) { return root.svc ? root.svc.tr(key, fallback) : fallback }

  // Cursor moves skip the day headers.
  function move(dx, dy) {
    if (dy === 0 || root.rows.length === 0) return
    var i = root.cursor < 0 ? (dy > 0 ? -1 : root.rows.length) : root.cursor
    do { i += dy } while (i >= 0 && i < root.rows.length && !root.rows[i].track)
    if (i < 0 || i >= root.rows.length) return
    root.cursor = i
    list.positionViewAtIndex(i, ListView.Contain)
  }
  function activate() {
    var r = root.rows[root.cursor]
    if (r && r.track) root.svc.play("", r.track.videoId, false)
  }
  function textKey(t) {
    var r = root.rows[root.cursor]
    if (t === "R" && root.svc) { root.svc.loadHistory(); return }
    if (r && r.track && root.panel) root.panel.trackKey(t, r.track)
  }

  Text {
    anchors.centerIn: parent
    visible: root.rows.length === 0
    textFormat: Text.PlainText
    text: root.svc && root.svc.historyLoading ? root.tr("history.loading", "Loading your history…") : root.tr("history.empty", "Nothing played yet")
    color: Color.foreground; opacity: 0.5
    font.family: root.family; font.pixelSize: Style.font.body
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    model: root.rows
    spacing: Style.space(2)
    boundsBehavior: Flickable.StopAtBounds
    delegate: Loader {
      id: row
      required property var modelData
      required property int index
      width: list.width
      sourceComponent: row.modelData.track ? trackRow : headerRow

      Component {
        id: headerRow
        Text {
          topPadding: row.index === 0 ? 0 : Style.space(8)
          bottomPadding: Style.space(2)
          textFormat: Text.PlainText
          text: row.modelData.header
          color: Color.foreground; opacity: 0.7
          font.family: root.family; font.pixelSize: Style.font.bodySmall; font.bold: true
        }
      }
      Component {
        id: trackRow
        TrackRow {
          width: list.width
          family: root.family
          track: row.modelData.track
          selected: root.cursor === row.index
          current: root.svc && root.svc.video === row.modelData.track.videoId
          actions: root.panel ? root.panel.trackActions : []
          onActivated: { root.cursor = row.index; root.activate() }
          onSecondary: root.svc.radio(row.modelData.track.videoId)
          onAction: function(name) { root.panel.trackAction(name, row.modelData.track) }
        }
      }
    }
  }
}
