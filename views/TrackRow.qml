import QtQuick
import qs.Ui
import qs.Commons

// One track: thumb, title / artist · album, duration. Used by the playlist,
// queue and search lists so they all look the same.
Rectangle {
  id: root
  property var track: ({})
  property string family: Style.font.family
  property bool selected: false      // keyboard cursor
  property bool current: false       // the track that is playing
  property bool showAlbum: true
  // Small buttons at the right, shown while the row is hovered or under the
  // keyboard cursor (they take the duration's place): [{name, icon, tip}].
  property var actions: []
  signal activated()
  signal secondary()                 // right click / radio
  signal action(string name)

  HoverHandler { id: rowHover }
  readonly property bool showActions: root.actions.length > 0 && (root.selected || rowHover.hovered)

  height: Style.space(40)
  radius: Style.cornerRadius
  color: selected ? Style.hoverFill : (hover.containsMouse ? Style.normalFill : "transparent")
  border.width: current ? Style.selectedBorderWidth : 0
  border.color: Color.accent

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(4)
    spacing: Style.space(8)

    Item {
      width: Style.space(32)
      height: Style.space(32)
      anchors.verticalCenter: parent.verticalCenter
      Rectangle { anchors.fill: parent; radius: Style.space(3); color: Style.normalFill; visible: thumb.status !== Image.Ready }
      Image {
        id: thumb
        anchors.fill: parent
        source: root.track && root.track.thumb ? root.track.thumb : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
      }
      Text {
        anchors.centerIn: parent
        visible: root.current
        textFormat: Text.PlainText
        text: "\u{F040A}"
        color: Color.accent
        font.family: root.family
        font.pixelSize: Style.font.body
        style: Text.Outline
        styleColor: Color.background
      }
    }

    Column {
      width: parent.width - Style.space(32) - (root.showActions ? actionRow.width : durText.width) - Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.track && root.track.title ? root.track.title : ""
        color: root.current ? Color.accent : Color.foreground
        font.family: root.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: {
          var t = root.track || {}
          var s = t.artist || ""
          if (root.showAlbum && t.album) s += (s ? "  ·  " : "") + t.album
          return s
        }
        color: Color.foreground
        opacity: 0.6
        font.family: root.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      id: durText
      visible: !root.showActions
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: (root.track && root.track.liked ? "\u{F02D1} " : "") + (root.track && root.track.dur ? root.track.dur : "")
      color: Color.foreground
      opacity: 0.5
      font.family: root.family
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.secondary(); else root.activated() }
  }

  // After the MouseArea, so the buttons get their own clicks.
  Row {
    id: actionRow
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)
    visible: root.showActions
    Repeater {
      model: root.actions
      delegate: PanelActionButton {
        required property var modelData
        iconText: modelData.icon
        tooltipText: modelData.tip
        fontFamily: root.family
        onClicked: root.action(modelData.name)
      }
    }
  }
}
