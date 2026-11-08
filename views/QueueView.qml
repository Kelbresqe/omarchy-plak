import QtQuick
import qs.Ui
import qs.Commons

// Up next, as the player has it. Enter jumps to a row.
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  readonly property var queue: svc ? svc.queue : ({ items: [], current: -1 })
  property int cursor: -1

  function move(dx, dy) {
    var n = root.queue.items.length
    if (n === 0) return
    var start = root.cursor < 0 ? Math.max(0, root.queue.current) : root.cursor
    root.cursor = Math.max(0, Math.min(n - 1, start + dy))
    list.positionViewAtIndex(root.cursor, ListView.Contain)
  }
  function activate() { if (root.cursor >= 0) root.svc.queueJump(root.cursor) }
  function textKey(t) { if (t === "g") { root.cursor = root.queue.current; list.positionViewAtIndex(Math.max(0, root.queue.current), ListView.Center) } }
  function tr(key, fallback) { return root.svc ? root.svc.tr(key, fallback) : fallback }

  Component.onCompleted: Qt.callLater(function() { if (root.queue.current >= 0) list.positionViewAtIndex(root.queue.current, ListView.Center) })

  Text {
    anchors.centerIn: parent
    visible: root.queue.items.length === 0
    textFormat: Text.PlainText
    text: root.tr("queue.empty", "Nothing queued — start a playlist")
    color: Color.foreground; opacity: 0.5
    font.family: root.family; font.pixelSize: Style.font.body
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(6)
    Text {
      textFormat: Text.PlainText
      text: root.queue.items.length > 0 && root.svc
        ? root.svc.trn("queue.header", root.queue.items.length, "Up next  ·  %1 tracks  ·  g jumps to the current one")
            .arg(I18n.formatNumber(root.queue.items.length))
        : ""
      color: Color.foreground; opacity: 0.5
      font.family: root.family; font.pixelSize: Style.font.caption
    }
    ListView {
      id: list
      width: parent.width
      height: parent.height - Style.space(20)
      clip: true
      model: root.queue.items
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      delegate: TrackRow {
        required property var modelData
        required property int index
        width: list.width
        family: root.family
        track: modelData
        selected: root.cursor === index
        current: root.queue.current === index
        onActivated: root.svc.queueJump(index)
        onSecondary: root.svc.radio(modelData.videoId)
      }
    }
  }
}
