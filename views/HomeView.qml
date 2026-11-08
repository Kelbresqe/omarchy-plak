import QtQuick
import qs.Ui
import qs.Commons

// Home: YouTube's rows for this account — Listen again, Mixed for you,
// Quick picks… One click (or Enter) starts a tile.
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  readonly property var shelves: svc ? svc.home : []
  property int row: 0
  property int col: 0
  readonly property int tile: Style.space(104)

  function move(dx, dy) {
    if (root.shelves.length === 0) return
    root.row = Math.max(0, Math.min(root.shelves.length - 1, root.row + dy))
    var n = root.shelves[root.row].items.length
    root.col = Math.max(0, Math.min(n - 1, root.col + dx))
    rows.positionViewAtIndex(root.row, ListView.Contain)
  }
  function activate() {
    var sh = root.shelves[root.row]
    if (sh && sh.items[root.col]) root.svc.playItem(sh.items[root.col])
  }
  function textKey(t) { if (t === "R" && root.svc) root.svc.loadHome() }
  function tr(key, fallback) { return root.svc ? root.svc.tr(key, fallback) : fallback }

  // Where the last session left off, while nothing is playing.
  readonly property var resume: root.svc && !root.svc.hasMedia ? root.svc.resume : null

  Text {
    anchors.centerIn: parent
    visible: root.shelves.length === 0
    textFormat: Text.PlainText
    text: root.svc && root.svc.homeLoading ? root.tr("home.loading", "Loading your home…") : root.tr("home.empty", "Nothing here yet")
    color: Color.foreground; opacity: 0.5
    font.family: root.family; font.pixelSize: Style.font.body
  }

  Button {
    id: resumeButton
    anchors.top: parent.top
    anchors.left: parent.left
    width: Math.min(implicitWidth, parent.width)
    visible: root.resume !== null
    height: visible ? implicitHeight : 0
    iconText: "\u{F040A}"
    // The title is appended, not passed through .arg(): a "%2" in a song
    // title would otherwise be filled in too.
    text: root.resume ? root.tr("resume.label", "Resume where you left off") + "  ·  "
      + root.resume.title + (root.resume.artist ? " — " + root.resume.artist : "")
      + "  (" + Math.floor(root.resume.time / 60) + ":" + ("0" + root.resume.time % 60).slice(-2) + ")" : ""
    bordered: true
    fontFamily: root.family
    onClicked: root.svc.resumePlay()
  }

  ListView {
    id: rows
    anchors.top: resumeButton.bottom
    anchors.topMargin: resumeButton.visible ? Style.space(8) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    model: root.shelves
    spacing: Style.space(8)
    boundsBehavior: Flickable.StopAtBounds

    delegate: Column {
      id: shelf
      required property var modelData
      required property int index
      width: rows.width
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: shelf.modelData.title
        color: root.row === shelf.index ? Color.accent : Color.foreground
        opacity: root.row === shelf.index ? 1 : 0.7
        font.family: root.family; font.pixelSize: Style.font.bodySmall; font.bold: true
      }

      ListView {
        id: strip
        width: parent.width
        height: root.tile + Style.space(34)
        orientation: ListView.Horizontal
        clip: true
        model: shelf.modelData.items
        spacing: Style.space(8)
        boundsBehavior: Flickable.StopAtBounds
        Connections {
          target: root
          function onColChanged() { if (root.row === shelf.index) strip.positionViewAtIndex(root.col, ListView.Contain) }
        }

        delegate: Item {
          id: card
          required property var modelData
          required property int index
          readonly property bool selected: root.row === shelf.index && root.col === card.index
          width: card.modelData.wide ? root.tile * 16 / 9 : root.tile
          height: strip.height

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: card.selected ? Style.hoverFill : (hover.containsMouse ? Style.normalFill : "transparent")
            border.width: card.selected ? Style.selectedBorderWidth : 0
            border.color: Style.selectedBorderColor
          }
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            spacing: Style.space(3)
            Item {
              width: parent.width
              height: root.tile - Style.space(8)
              Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: Style.normalFill; visible: cover.status !== Image.Ready }
              Image {
                id: cover
                anchors.fill: parent
                source: card.modelData.thumb || ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
              }
              // Kind badge, bottom-right: play for songs, list for playlists/mixes, disc for albums.
              Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(3)
                textFormat: Text.PlainText
                text: card.modelData.kind === "song" ? "\u{F040A}" : card.modelData.kind === "album" ? "\u{F0025}" : "\u{F0CB8}"
                color: Color.foreground
                font.family: root.family; font.pixelSize: Style.font.caption
                style: Text.Outline; styleColor: Color.background
                opacity: 0.85
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.modelData.title
              color: Color.foreground
              font.family: root.family; font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: card.modelData.subtitle
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
            onClicked: { root.row = shelf.index; root.col = card.index; root.svc.playItem(card.modelData) }
          }
        }
      }
    }
  }
}
