import QtQuick
import qs.Ui
import qs.Commons

// Library: a grid of the account's playlists; Enter drills into one, where
// Enter on a row plays it in that playlist's context. Left / Backspace go back.
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  property var openList: null          // {id,title,...} when drilled in
  property var rows: []                // parsed tracks of openList
  property string openPlaylistId: ""   // playlist id YouTube reports (albums map to one)
  property bool loading: false
  property int cursor: 0
  readonly property int columns: 3
  readonly property var library: svc ? svc.library : []

  function move(dx, dy) {
    if (root.openList) {
      if (dx < 0) { root.back(); return }
      root.cursor = clamp(root.cursor + dy, root.rows.length)
      list.positionViewAtIndex(root.cursor, ListView.Contain)
      return
    }
    var n = root.library.length
    root.cursor = clamp(root.cursor + dx + dy * root.columns, n)
    grid.positionViewAtIndex(root.cursor, GridView.Contain)
  }
  function clamp(i, n) { return n === 0 ? 0 : Math.max(0, Math.min(n - 1, i)) }

  function activate() {
    if (root.openList) {
      var t = root.rows[root.cursor]
      if (t) root.svc.play(root.openPlaylistId || root.openList.id, t.videoId, false)
      return
    }
    var p = root.library[root.cursor]
    if (p) root.open(p)
  }

  function textKey(t) {
    if (root.openList && root.panel && root.panel.trackKey(t, root.rows[root.cursor])) return
    if (t === "s" && root.openList) root.svc.play(root.openPlaylistId || root.openList.id, "", true)
    if (t === "a" && root.openList) root.svc.play(root.openPlaylistId || root.openList.id, "", false)
    if (t === "\b") root.back()
  }

  function open(p) {
    root.openList = p
    root.rows = []
    root.openPlaylistId = ""
    root.cursor = 0
    root.loading = true
    root.svc.loadPlaylist(p.id, function(r) {
      root.loading = false
      if (!r || root.openList !== p) return
      root.rows = r.items
      root.openPlaylistId = r.playlistId
    })
  }

  function back() {
    root.openList = null
    root.rows = []
    root.cursor = 0
  }
  function tr(key, fallback) { return root.svc ? root.svc.tr(key, fallback) : fallback }

  Text {
    anchors.centerIn: parent
    visible: !root.openList && root.library.length === 0
    textFormat: Text.PlainText
    text: root.svc && root.svc.libraryLoading ? root.tr("playlists.loading", "Loading your library…") : root.tr("playlists.empty", "No playlists yet")
    color: Color.foreground; opacity: 0.5
    font.family: root.family; font.pixelSize: Style.font.body
  }

  GridView {
    id: grid
    anchors.fill: parent
    visible: !root.openList
    clip: true
    model: root.library
    cellWidth: Math.floor(width / root.columns)
    cellHeight: cellWidth + Style.space(40)
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: cell
      required property var modelData
      required property int index
      width: grid.cellWidth
      height: grid.cellHeight

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        radius: Style.cornerRadius
        color: root.cursor === cell.index ? Style.hoverFill : (hover.containsMouse ? Style.normalFill : "transparent")
        border.width: root.cursor === cell.index ? Style.selectedBorderWidth : 0
        border.color: Style.selectedBorderColor

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: parent.width - Style.space(16)
            Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: Style.normalFill; visible: cover.status !== Image.Ready }
            Image {
              id: cover
              anchors.fill: parent
              source: cell.modelData.thumb || ""
              asynchronous: true
              fillMode: Image.PreserveAspectCrop
              visible: status === Image.Ready
            }
            Text {
              anchors.centerIn: parent
              visible: cover.status !== Image.Ready
              textFormat: Text.PlainText
              text: cell.modelData.id === "LM" ? "\u{F02D1}" : "\u{F0CB8}"
              color: Color.foreground; opacity: 0.5
              font.family: root.family; font.pixelSize: Style.font.displayLarge
            }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: cell.modelData.title || ""
            color: Color.foreground
            font.family: root.family; font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: (cell.modelData.count > 0 ? cell.modelData.count + " songs" : "") +
                  (cell.modelData.author && cell.modelData.count > 0 ? "  ·  " : "") + (cell.modelData.author || "")
            color: Color.foreground; opacity: 0.5
            font.family: root.family; font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            root.cursor = cell.index
            if (mouse.button === Qt.RightButton) root.svc.play(cell.modelData.id, "", true)
            else root.open(cell.modelData)
          }
        }
      }
    }
  }

  // Drilled-in playlist.
  Column {
    anchors.fill: parent
    visible: root.openList !== null
    spacing: Style.space(6)

    Row {
      width: parent.width
      spacing: Style.space(8)
      PanelActionButton {
        iconText: "\u{F004D}"
        tooltipText: root.tr("playlists.back", "Back (←)")
        fontFamily: root.family
        onClicked: root.back()
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(190)
        textFormat: Text.PlainText
        text: root.openList ? root.openList.title : ""
        color: Color.foreground
        font.family: root.family; font.pixelSize: Style.font.subtitle; font.bold: true
        elide: Text.ElideRight
      }
      Button {
        text: root.tr("playlists.play", "Play")
        iconText: "\u{F040A}"
        fontFamily: root.family
        bordered: true
        onClicked: root.svc.play(root.openPlaylistId || root.openList.id, "", false)
      }
      Button {
        text: root.tr("playlists.shuffle", "Shuffle")
        iconText: "\u{F049D}"
        fontFamily: root.family
        bordered: true
        onClicked: root.svc.play(root.openPlaylistId || root.openList.id, "", true)
      }
    }

    Text {
      visible: root.loading
      textFormat: Text.PlainText
      text: root.tr("common.loading", "Loading…")
      color: Color.foreground; opacity: 0.5
      font.family: root.family; font.pixelSize: Style.font.bodySmall
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - Style.space(40)
      clip: true
      model: root.rows
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      delegate: TrackRow {
        required property var modelData
        required property int index
        width: list.width
        family: root.family
        track: modelData
        selected: root.cursor === index
        current: root.svc && root.svc.video === modelData.videoId
        onActivated: { root.cursor = index; root.svc.play(root.openPlaylistId || root.openList.id, modelData.videoId, false) }
        onSecondary: root.svc.radio(modelData.videoId)
        actions: root.panel ? root.panel.trackActions : []
        onAction: function(name) { root.panel.trackAction(name, modelData) }
      }
    }
  }
}
