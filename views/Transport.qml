import QtQuick
import qs.Ui
import qs.Commons

// Footer: seek bar, transport, like/radio, volume. Bound to the MPRIS player
// via the service; account actions go to the bridge.
Column {
  id: root
  property var svc: null
  property var bar: null
  property string family: Style.font.family
  spacing: Style.space(6)

  readonly property var player: svc ? svc.player : null
  readonly property bool canSeek: player && player.canSeek && player.lengthSupported && player.length > 0
  property bool seeking: false

  function fmt(sec) {
    sec = Math.max(0, Math.floor(sec || 0))
    var m = Math.floor(sec / 60), s = sec % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  Row {
    width: parent.width
    spacing: Style.space(8)
    Text {
      id: posText
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.fmt(seek.dragging ? seek.liveValue : (root.player ? root.player.position : 0))
      color: Color.foreground; opacity: 0.6
      font.family: root.family; font.pixelSize: Style.font.caption
      width: Style.space(34)
    }
    PanelSlider {
      id: seek
      width: parent.width - posText.width - lenText.width - Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      minimum: 0
      maximum: root.player && root.player.lengthSupported ? Math.max(1, root.player.length) : 1
      value: root.player ? root.player.position : 0
      step: 1
      enabled: root.canSeek
      onReleased: function(v) { if (root.svc) root.svc.seekTo(v) }
    }
    Text {
      id: lenText
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.fmt(root.player && root.player.lengthSupported ? root.player.length : 0)
      color: Color.foreground; opacity: 0.6
      font.family: root.family; font.pixelSize: Style.font.caption
      width: Style.space(34)
      horizontalAlignment: Text.AlignRight
    }
  }

  Item {
    width: parent.width
    height: Style.space(30)

    // Left: like / dislike / radio (account actions).
    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      PanelActionButton {
        iconText: root.svc && root.svc.liked === "LIKE" ? "\u{F0513}" : "\u{F0514}"
        foreground: root.svc && root.svc.liked === "LIKE" ? Color.accent : Color.foreground
        tooltipText: "Like (f)"
        fontFamily: root.family
        enabled: root.svc && root.svc.ready && root.svc.video !== ""
        onClicked: root.svc.toggleLike()
      }
      PanelActionButton {
        iconText: root.svc && root.svc.liked === "DISLIKE" ? "\u{F0511}" : "\u{F0512}"
        foreground: root.svc && root.svc.liked === "DISLIKE" ? Color.urgent : Color.foreground
        tooltipText: "Dislike (d)"
        fontFamily: root.family
        enabled: root.svc && root.svc.ready && root.svc.video !== ""
        onClicked: root.svc.dislike()
      }
      PanelActionButton {
        iconText: "\u{F043B}"
        tooltipText: "Start radio from this song (r)"
        fontFamily: root.family
        enabled: root.svc && root.svc.ready && root.svc.video !== ""
        onClicked: root.svc.radio(root.svc.video)
      }
    }

    // Centre: transport.
    Row {
      anchors.centerIn: parent
      spacing: Style.space(6)
      PanelActionButton {
        iconText: "\u{F04AE}"
        tooltipText: "Previous (,)"
        fontFamily: root.family
        enabled: root.player && root.player.canGoPrevious
        onClicked: root.svc.previous()
      }
      PanelActionButton {
        iconText: root.player && root.player.isPlaying ? "\u{F03E4}" : "\u{F040A}"
        tooltipText: root.player && root.player.isPlaying ? "Pause (Space)" : "Play (Space)"
        fontFamily: root.family
        fontSize: Style.font.display
        size: Style.space(30)
        enabled: root.player !== null
        onClicked: root.svc.togglePlaying()
      }
      PanelActionButton {
        iconText: "\u{F04AD}"
        tooltipText: "Next (.)"
        fontFamily: root.family
        enabled: root.player && root.player.canGoNext
        onClicked: root.svc.next()
      }
    }

    // Right: repeat, volume, show window.
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      PanelActionButton {
        readonly property string mode: root.svc ? root.svc.repeatMode : ""
        iconText: mode === "ONE" ? "\u{F0458}" : mode === "ALL" ? "\u{F0456}" : "\u{F0457}"
        foreground: mode === "ALL" || mode === "ONE" ? Color.accent : Color.foreground
        tooltipText: mode === "ONE" ? "Repeat: this song (t)" : mode === "ALL" ? "Repeat: all (t)" : "Repeat: off (t)"
        fontFamily: root.family
        visible: root.svc && root.svc.repeatSupported
        onClicked: root.svc.cycleRepeat()
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "\u{F057E}"
        color: Color.foreground; opacity: 0.6
        font.family: root.family; font.pixelSize: Style.font.icon
        visible: root.svc && root.svc.volumeSupported
      }
      PanelSlider {
        width: Style.space(70)
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        visible: root.svc && root.svc.volumeSupported
        value: root.svc && root.svc.volume >= 0 ? root.svc.volume : 0
        onMoved: function(v) { if (root.svc) root.svc.setVolume(v) }
      }
      PanelActionButton {
        iconText: root.svc && root.svc.sleepMinutesLeft > 0 ? "\u{F04B2}" : "\u{F04B2}"
        foreground: root.svc && root.svc.sleepMinutesLeft > 0 ? Color.accent : Color.foreground
        tooltipText: root.svc && root.svc.sleepMinutesLeft > 0
          ? "Sleep in " + root.svc.sleepMinutesLeft + " min (click to change)"
          : "Sleep timer: 15 / 30 / 60 min"
        fontFamily: root.family
        onClicked: if (root.svc) root.svc.cycleSleep()
      }
      PanelActionButton {
        iconText: "\u{F03CC}"
        tooltipText: "Show the YouTube Music window"
        fontFamily: root.family
        onClicked: if (root.svc) root.svc.revealApp()
      }
    }
  }
}
