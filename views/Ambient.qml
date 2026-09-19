import QtQuick
import QtQuick.Effects
import qs.Commons
import "../Glow.js" as Glow

// YouTube's "ambient mode", clamped to the theme: the album art blown up,
// blurred hard, drifting slowly, at a whisper of opacity. Two images so a
// track change crossfades instead of popping.
Item {
  id: root
  property var svc: null
  readonly property string artUrl: svc ? svc.artUrl : ""
  readonly property bool playing: svc ? svc.isPlaying : false
  clip: true

  property int front: 0
  onArtUrlChanged: {
    var next = root.front === 0 ? imgB : imgA
    next.source = root.artUrl
  }

  function swapIfReady(img, slot) {
    if (img.status === Image.Ready && img.source == root.artUrl) root.front = slot
  }

  Item {
    id: drift
    anchors.centerIn: parent
    width: parent.width * 1.3
    height: parent.height * 1.3
    // A very slow figure-eight so the wash is never quite still.
    SequentialAnimation on x {
      loops: Animation.Infinite
      running: root.visible
      NumberAnimation { from: -root.width * 0.15; to: -root.width * 0.15 - root.width * 0.06; duration: 30000; easing.type: Easing.InOutSine }
      NumberAnimation { to: -root.width * 0.15; duration: 30000; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on y {
      loops: Animation.Infinite
      running: root.visible
      NumberAnimation { from: -root.height * 0.15; to: -root.height * 0.15 + root.height * 0.05; duration: 41000; easing.type: Easing.InOutSine }
      NumberAnimation { to: -root.height * 0.15; duration: 41000; easing.type: Easing.InOutSine }
    }

    Image {
      id: imgA
      anchors.fill: parent
      source: root.artUrl
      asynchronous: true
      fillMode: Image.PreserveAspectCrop
      visible: false
      onStatusChanged: root.swapIfReady(imgA, 0)
    }
    Image {
      id: imgB
      anchors.fill: parent
      asynchronous: true
      fillMode: Image.PreserveAspectCrop
      visible: false
      onStatusChanged: root.swapIfReady(imgB, 1)
    }
    MultiEffect {
      anchors.fill: parent
      source: imgA
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      saturation: 0.2
      opacity: root.front === 0 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 900 } }
    }
    MultiEffect {
      anchors.fill: parent
      source: imgB
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      saturation: 0.2
      opacity: root.front === 1 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 900 } }
    }
  }

  // Whole wash sits at a whisper; the theme background always wins.
  opacity: root.playing ? 0.28 : 0.14
  Behavior on opacity { NumberAnimation { duration: 800 } }
}
