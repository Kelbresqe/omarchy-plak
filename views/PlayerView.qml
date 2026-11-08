import QtQuick
import qs.Ui
import qs.Commons
import QtQuick.Effects

// Now playing: big art, title, artist, album. Space toggles playback.
Item {
  id: root
  property var svc: null
  property var panel: null
  property string family: Style.font.family
  readonly property bool inputActive: false

  // ← / → seek 10 s. Enter / Space resumes the last session while nothing
  // plays, and toggles playback otherwise.
  function move(dx, dy) { if (svc && dx !== 0) svc.seekBy(dx * 10) }
  function activate() {
    if (!svc) return
    if (!svc.hasMedia && svc.resume) svc.resumePlay()
    else svc.togglePlaying()
  }
  function textKey(t) { }
  function tr(key, fallback) { return root.svc ? root.svc.tr(key, fallback) : fallback }

  Component.onCompleted: if (svc) svc.cavaWanted = true
  Component.onDestruction: if (svc) svc.cavaWanted = false
  onSvcChanged: if (svc) svc.cavaWanted = true

  readonly property int artSize: Math.min(Style.space(250), height - Style.space(24))

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(16)

    Item {
      id: artBox
      width: root.artSize
      height: root.artSize
      anchors.verticalCenter: parent.verticalCenter

      // Soft glow behind the art. Colour comes from ArtGlow, mixed toward the
      // theme accent so every theme keeps its own temperature.
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + Style.space(24)
        height: parent.height + Style.space(24)
        radius: width / 2
        color: glow.color
        opacity: root.svc && root.svc.isPlaying ? 0.22 : 0.10
        Behavior on opacity { NumberAnimation { duration: 600 } }
        Behavior on color { ColorAnimation { duration: 600 } }
      }
      Rectangle {
        anchors.centerIn: parent
        width: parent.width + Style.space(8)
        height: parent.height + Style.space(8)
        radius: width / 2
        color: glow.color
        opacity: root.svc && root.svc.isPlaying ? 0.30 : 0.14
        Behavior on opacity { NumberAnimation { duration: 600 } }
        Behavior on color { ColorAnimation { duration: 600 } }
      }

      // The record. Art masked to a disc, faint grooves, a hole in the middle,
      // spinning at 33⅓-ish while playing and easing to a stop when paused.
      Item {
        id: disc
        anchors.fill: parent
        property real angle: 0
        property real speed: root.svc && root.svc.isPlaying ? 30 : 0      // degrees per second
        Behavior on speed { NumberAnimation { duration: 1500; easing.type: Easing.OutCubic } }
        rotation: angle
        FrameAnimation {
          running: disc.speed > 0.01
          onTriggered: disc.angle = (disc.angle + disc.speed * frameTime) % 360
        }

        // The disc backing doubles as the mask: an invisible layered item is
        // not rendered, so the mask has to be something that is on screen.
        Rectangle {
          id: discMask
          anchors.fill: parent
          radius: width / 2
          color: Color.background
          layer.enabled: true
        }
        // Two images so a new track crossfades in rather than popping.
        Image {
          id: artA
          anchors.fill: parent
          source: root.svc ? root.svc.artUrl : ""
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          visible: false
          onStatusChanged: if (status === Image.Ready && String(source) === (root.svc ? root.svc.artUrl : "")) disc.front = 0
        }
        Image {
          id: artB
          anchors.fill: parent
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          visible: false
          onStatusChanged: if (status === Image.Ready && String(source) === (root.svc ? root.svc.artUrl : "")) disc.front = 1
        }
        property int front: 0
        Connections {
          target: root.svc
          function onArtUrlChanged() { (disc.front === 0 ? artB : artA).source = root.svc.artUrl }
        }

        MultiEffect {
          anchors.fill: parent
          source: artA
          maskEnabled: true
          maskSource: discMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
          opacity: disc.front === 0 ? 1 : 0
          scale: disc.front === 0 ? 1 : 0.94
          Behavior on opacity { NumberAnimation { duration: 400 } }
          Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        MultiEffect {
          anchors.fill: parent
          source: artB
          maskEnabled: true
          maskSource: discMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
          opacity: disc.front === 1 ? 1 : 0
          scale: disc.front === 1 ? 1 : 0.94
          Behavior on opacity { NumberAnimation { duration: 400 } }
          Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        // Grooves.
        Canvas {
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var c = width / 2
            ctx.strokeStyle = Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.28)
            ctx.lineWidth = 1
            for (var r = c * 0.3; r < c - 2; r += 5) { ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke() }
          }
        }
        // Label ring + spindle hole.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.3; height: width; radius: width / 2
          color: "transparent"
          border.width: 2
          border.color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55)
        }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(12); height: width; radius: width / 2
          color: Color.background
          border.width: 1
          border.color: Color.accent
        }
        Text {
          anchors.centerIn: parent
          visible: artA.status !== Image.Ready && artB.status !== Image.Ready
          textFormat: Text.PlainText
          text: "\u{F075A}"
          color: Color.foreground; opacity: 0.4
          font.family: root.family; font.pixelSize: Style.font.displayLarge
        }
      }
      // ArtGlow samples the plain image, not the masked effect.
      Image { id: art; source: root.svc ? root.svc.artUrl : ""; asynchronous: true; visible: false; width: 8; height: 8 }

      ArtGlow {
        id: glow
        source: art
        accent: Color.accent
        background: Color.background
      }
    }

    Column {
      width: parent.width - artBox.width - Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.svc && root.svc.title ? root.svc.title : root.tr("common.nothingPlaying", "Nothing playing")
        color: Color.foreground
        font.family: root.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.svc ? root.svc.artist : ""
        color: Color.accent
        font.family: root.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.svc ? root.svc.album : ""
        color: Color.foreground
        opacity: 0.6
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        visible: text !== ""
      }
      // Nothing playing: offer where the last session left off.
      Button {
        readonly property var resume: root.svc && !root.svc.hasMedia ? root.svc.resume : null
        visible: resume !== null
        width: Math.min(implicitWidth, parent.width)
        iconText: "\u{F040A}"
        text: resume ? root.tr("resume.label", "Resume where you left off") : ""
        tooltipText: resume ? resume.title + (resume.artist ? " — " + resume.artist : "") : ""
        bordered: true
        fontFamily: root.family
        onClicked: root.svc.resumePlay()
      }
      Item { width: 1; height: Style.space(6) }

      // Spectrum bars (cava). Zero height when cava is absent or idle, so
      // nothing in the layout hints at a feature that is not there.
      Row {
        id: bars
        readonly property var levels: root.svc ? root.svc.spectrum : []
        visible: levels.length > 0
        height: visible ? Style.space(28) : 0
        spacing: Style.space(3)
        Repeater {
          model: bars.levels.length
          delegate: Rectangle {
            required property int index
            anchors.bottom: parent.bottom
            width: Style.space(6)
            height: Math.max(2, bars.height * (bars.levels[index] || 0))
            radius: Style.space(2)
            color: Color.accent
            opacity: 0.35 + 0.5 * (bars.levels[index] || 0)
            Behavior on height { NumberAnimation { duration: 60 } }
          }
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: {
          if (!root.svc) return ""
          var q = root.svc.queue
          if (!q || q.items.length === 0) return ""
          // YouTube pairs each song with its video version in the queue;
          // the first entry with a different title is the real next track.
          var norm = function(t) { return String(t || "").replace(/\s*[\(\[][^\)\]]*[\)\]]\s*$/, "").toLowerCase() }
          var cur = q.current >= 0 ? q.items[q.current] : null
          var next = null
          for (var i = q.current + 1; i < q.items.length && q.current >= 0; i++) {
            if (!cur || norm(q.items[i].title) !== norm(cur.title)) { next = q.items[i]; break }
          }
          return next ? root.tr("player.upNext", "Up next:") + "  " + next.title + (next.artist ? "  ·  " + next.artist : "") : ""
        }
        color: Color.foreground
        opacity: 0.5
        font.family: root.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        visible: text !== ""
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        // Key/label pairs are joined with no-break spaces (also in the
        // catalogs) so they never wrap apart.
        text: root.tr("player.keys", "Space\u00a0play/\u2060pause  ·  ,\u00a0.\u00a0prev/\u2060next  ·  ←\u00a0→\u00a0seek  ·  f\u00a0like  ·  r\u00a0radio  ·  t\u00a0repeat  ·  m\u00a0shuffle  ·  b\u00a0save  ·  Tab\u00a0views")
        color: Color.foreground
        opacity: 0.35
        font.family: root.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }
  }
}
