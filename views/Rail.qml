import QtQuick
import qs.Ui
import qs.Commons

// Vertical strip of view switchers. Glyphs are Nerd Font (Material range).
Column {
  id: root
  property string family: Style.font.family
  property string current: "player"
  signal selected(string name)

  width: Style.space(34)
  spacing: Style.space(4)

  readonly property var entries: [
    { name: "home",      glyph: "\u{F02DC}", tip: "Home (h)" },
    { name: "player",    glyph: "\u{F075A}", tip: "Now playing (n)" },
    { name: "playlists", glyph: "\u{F0CB8}", tip: "Playlists (p)" },
    { name: "queue",     glyph: "\u{F0411}", tip: "Up next (q)" },
    { name: "history",   glyph: "\u{F02DA}", tip: "History (i)" },
    { name: "lyrics",    glyph: "\u{F036C}", tip: "Lyrics (y)" },
    { name: "search",    glyph: "\u{F0349}", tip: "Search (/)" }
  ]

  Repeater {
    model: root.entries
    delegate: Rectangle {
      required property var modelData
      width: root.width
      height: root.width
      radius: Style.cornerRadius
      color: root.current === modelData.name ? Style.hoverFill : (hover.containsMouse ? Style.normalFill : "transparent")
      border.width: root.current === modelData.name ? Style.selectedBorderWidth : 0
      border.color: Color.accent

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: parent.modelData.glyph
        color: root.current === parent.modelData.name ? Color.accent : Color.foreground
        opacity: root.current === parent.modelData.name ? 1 : 0.7
        font.family: root.family
        font.pixelSize: Style.font.icon
      }
      MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.selected(parent.modelData.name)
      }
    }
  }
}
