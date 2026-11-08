import QtQuick
import qs.Ui
import qs.Commons

// The Plak wordmark, centered, with an equalizer underline that breathes
// while playing and follows cava when it is present.
Item {
  id: root
  property var svc: null
  property string family: Style.font.family
  readonly property bool playing: svc ? svc.isPlaying : false
  readonly property var spectrum: svc ? svc.spectrum : []

  height: Style.space(44)

  Row {
    id: mark
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    spacing: Style.space(8)

    // A record in the theme's colours: disc, label, spindle hole.
    Rectangle {
      id: disc
      anchors.verticalCenter: parent.verticalCenter
      width: word.implicitHeight * 0.8
      height: width
      radius: width / 2
      color: Color.accent
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.38
        height: width
        radius: width / 2
        color: Color.background
        Rectangle { anchors.centerIn: parent; width: 3; height: 3; radius: 1.5; color: Color.accent }
      }
    }
    Text {
      id: word
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "Plak"
      color: Color.foreground
      font.family: root.family
      font.pixelSize: Style.font.display
      font.bold: true
      font.letterSpacing: 1
    }
  }

  // Equalizer underline: 24 bars. With cava, real bins; without, a slow
  // breathing wave while playing and a flat line when paused.
  Row {
    id: eq
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: mark.bottom
    anchors.topMargin: Style.space(4)
    spacing: 3
    height: Style.space(12)
    readonly property int count: 24
    property real phase: 0
    NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 2400; loops: Animation.Infinite; running: root.playing && root.spectrum.length === 0 }

    Repeater {
      model: eq.count
      delegate: Rectangle {
        required property int index
        readonly property real level: {
          if (root.spectrum.length > 0) {
            var k = Math.floor(index * root.spectrum.length / eq.count)
            return root.spectrum[k] || 0
          }
          if (!root.playing) return 0.15
          return 0.3 + 0.7 * Math.abs(Math.sin(eq.phase + index * 0.45)) * (0.6 + 0.4 * Math.abs(Math.sin(index * 1.7)))
        }
        anchors.bottom: parent.bottom
        width: Style.space(4)
        height: Math.max(2, eq.height * level)
        radius: 2
        color: Color.accent
        opacity: 0.35 + 0.6 * level
        Behavior on height { NumberAnimation { duration: root.spectrum.length > 0 ? 50 : 300 } }
      }
    }
  }
}
