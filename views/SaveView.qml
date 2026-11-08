import QtQuick
import qs.Ui
import qs.Commons

// Save to playlist: the account's playlists that can take the song
// (playlist/get_add_to_playlist), with a check on the ones that already
// have it. Enter or a click saves and goes back; ← / Backspace go back
// without saving. The picker idea comes from Dqckey's
// omarchy-ytmusic-player (MIT).
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  readonly property var track: root.svc ? root.svc.saveTrack : null
  readonly property var targets: root.svc ? root.svc.saveTargets : []
  property int cursor: 0
  property string savedId: ""

  function tr(key, fallback) { return root.svc ? root.svc.tr(key, fallback) : fallback }
  function back() { if (root.panel) root.panel.closeSave() }

  function move(dx, dy) {
    if (dx < 0) { root.back(); return }
    if (root.targets.length === 0) return
    root.cursor = Math.max(0, Math.min(root.targets.length - 1, root.cursor + dy))
    list.positionViewAtIndex(root.cursor, ListView.Contain)
  }
  function activate() { var t = root.targets[root.cursor]; if (t) root.save(t) }
  function textKey(t) { if (t === "\b") root.back() }

  function save(t) {
    if (t.contains) { root.svc.osd(root.tr("osd.alreadySaved", "Already in that playlist")); return }
    root.svc.saveTo(t.id, function(ok) {
      if (!ok) return
      root.savedId = t.id
      closeLater.start()
    })
  }
  Timer { id: closeLater; interval: 600; onTriggered: root.back() }

  Column {
    anchors.fill: parent
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
      Column {
        width: parent.width - Style.space(40)
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.tr("save.title", "Save to playlist")
          color: Color.foreground
          font.family: root.family; font.pixelSize: Style.font.subtitle; font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.track ? root.track.title + (root.track.artist ? "  ·  " + root.track.artist : "") : ""
          color: Color.accent
          font.family: root.family; font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }

    Text {
      visible: root.targets.length === 0
      textFormat: Text.PlainText
      text: root.svc && root.svc.saveLoading ? root.tr("save.loading", "Loading your playlists…") : root.tr("save.none", "No playlists you can add to")
      color: Color.foreground; opacity: 0.5
      font.family: root.family; font.pixelSize: Style.font.bodySmall
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - Style.space(52)
      clip: true
      model: root.targets
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      delegate: Rectangle {
        id: target
        required property var modelData
        required property int index
        readonly property bool has: modelData.contains || root.savedId === modelData.id
        width: list.width
        height: Style.space(32)
        radius: Style.cornerRadius
        color: root.cursor === index ? Style.hoverFill : (hover.containsMouse ? Style.normalFill : "transparent")
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.right: mark.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: target.modelData.title
          color: Color.foreground
          opacity: target.modelData.contains ? 0.55 : 1
          font.family: root.family; font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          id: mark
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          visible: target.has
          textFormat: Text.PlainText
          text: "\u{F0E1E}"
          color: Color.accent
          font.family: root.family; font.pixelSize: Style.font.body
        }
        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.cursor = target.index; root.save(target.modelData) }
        }
      }
    }
  }
}
