import QtQuick
import qs.Ui
import qs.Commons

// Lyrics for the current track. Timed lines follow playback and can be
// clicked to seek; otherwise the plain text scrolls.
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  readonly property var lyrics: svc ? svc.lyrics : null
  readonly property var timed: lyrics && lyrics.timed ? lyrics.timed : []
  readonly property real posMs: svc && svc.player ? svc.player.position * 1000 : 0
  readonly property int current: {
    var idx = -1
    for (var i = 0; i < root.timed.length; i++) if (root.timed[i].t <= root.posMs) idx = i
    return idx
  }
  property bool userScrolled: false

  function move(dx, dy) { root.userScrolled = true; list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + dy * Style.space(40))) }
  function activate() { if (svc) svc.togglePlaying() }
  function textKey(t) { if (t === "g") { root.userScrolled = false; root.follow() } }

  function follow() {
    if (root.userScrolled || root.current < 0) return
    list.positionViewAtIndex(root.current, ListView.Center)
  }
  onCurrentChanged: root.follow()
  onTimedChanged: { root.userScrolled = false; Qt.callLater(root.follow) }

  // Re-arm auto-follow a while after the user scrolls away.
  Timer { id: rearm; interval: 8000; onTriggered: { root.userScrolled = false; root.follow() } }
  onUserScrolledChanged: if (userScrolled) rearm.restart()

  Text {
    anchors.centerIn: parent
    width: parent.width - Style.space(20)
    visible: root.timed.length === 0 && !(root.lyrics && root.lyrics.plain)
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    text: {
      if (!root.svc || !root.svc.video) return "Nothing playing"
      if (root.svc.lyricsLoading) return "Looking up lyrics…"
      return "No lyrics for this track"
    }
    color: Color.foreground; opacity: 0.5
    font.family: root.family; font.pixelSize: Style.font.body
  }

  // Timed lines.
  ListView {
    id: list
    anchors.fill: parent
    visible: root.timed.length > 0
    clip: true
    model: root.timed
    spacing: Style.space(4)
    boundsBehavior: Flickable.StopAtBounds
    onMovementStarted: root.userScrolled = true
    header: Item { width: 1; height: list.height / 2 - Style.space(20) }
    footer: Item { width: 1; height: list.height / 2 }

    delegate: Item {
      required property var modelData
      required property int index
      width: list.width
      height: line.implicitHeight + Style.space(6)

      Text {
        id: line
        width: parent.width - Style.space(16)
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: modelData.line
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        color: index === root.current ? Color.accent : Color.foreground
        opacity: index === root.current ? 1 : (index < root.current ? 0.35 : 0.6)
        font.family: root.family
        font.pixelSize: index === root.current ? Style.font.subtitle : Style.font.body
        font.bold: index === root.current
        Behavior on opacity { NumberAnimation { duration: 200 } }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.svc.seekTo(modelData.t / 1000); root.userScrolled = false }
      }
    }
  }

  // Plain text fallback.
  Flickable {
    id: plain
    anchors.fill: parent
    visible: root.timed.length === 0 && !!(root.lyrics && root.lyrics.plain)
    clip: true
    contentHeight: plainText.implicitHeight + Style.space(20)
    boundsBehavior: Flickable.StopAtBounds
    Text {
      id: plainText
      width: plain.width - Style.space(16)
      x: Style.space(8)
      textFormat: Text.PlainText
      text: root.lyrics && root.lyrics.plain ? root.lyrics.plain : ""
      wrapMode: Text.Wrap
      color: Color.foreground
      opacity: 0.8
      font.family: root.family; font.pixelSize: Style.font.body
      lineHeight: 1.3
    }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.margins: Style.space(4)
    visible: root.lyrics && root.lyrics.source !== ""
    textFormat: Text.PlainText
    text: root.lyrics ? root.lyrics.source : ""
    color: Color.foreground; opacity: 0.35
    font.family: root.family; font.pixelSize: Style.font.caption
  }
}
