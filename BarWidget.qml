import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// The now-playing pill: art thumb, "title · artist", and a hairline progress
// bar along the bottom edge. Click for the panel.
BarWidget {
  id: root
  moduleName: "tiertek.ytm"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("tiertek.ytm") : null

  // The service owns no settings; it reads ours.
  function pushSettings() { if (root.svc) root.svc.settings = root.settings }
  onSvcChanged: { pushSettings(); injectPanel() }
  onSettingsChanged: { pushSettings(); injectPanel() }
  Component.onCompleted: pushSettings()

  readonly property bool hasMedia: svc ? svc.hasMedia : false
  readonly property bool isPlaying: svc ? svc.isPlaying : false
  readonly property string title: svc ? svc.title : ""
  readonly property string artist: svc ? svc.artist : ""
  readonly property string artUrl: svc ? svc.artUrl : ""
  readonly property real progress: {
    if (!svc || !svc.player || !svc.player.lengthSupported || svc.player.length <= 0) return 0
    return Math.max(0, Math.min(1, svc.player.position / svc.player.length))
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  onOpenedChanged: if (root.svc) root.svc.panelOpen = root.opened
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: body.width

  readonly property bool showIdle: root.setting("showWhenIdle", true)
  readonly property real maxLabelWidth: Number(root.setting("maxLabelWidth", 180)) || 180
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color dimFg: Qt.darker(fg, 1.5)

  visible: hasMedia || showIdle
  implicitWidth: visible ? body.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function showView(name) { if (panelLoader.item) { panelLoader.item.show(name); panelLoader.item.open() } }
  // Save the playing song to a playlist: the panel opens on the picker.
  function saveCurrent() {
    var p = panelLoader.item
    if (!p || !root.svc || !root.svc.video) return
    p.openSave({ videoId: root.svc.video, title: root.svc.title, artist: root.svc.artist })
    p.open()
  }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var p = panelLoader.item
    if (!p) return
    p.bar = root.bar
    p.settings = root.settings
    p.anchorItem = root
    p.hostWidget = root
    p.svc = root.svc
  }
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "tiertek.ytm"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function view(name: string): void { root.showView(name) }
    function playPause(): void { if (root.svc) root.svc.togglePlaying() }
    function next(): void { if (root.svc) root.svc.next() }
    function prev(): void { if (root.svc) root.svc.previous() }
    function like(): void { if (root.svc) root.svc.toggleLike() }
    function reveal(): void { if (root.svc) root.svc.revealApp() }
    function hide(): void { if (root.svc) root.svc.hideApp() }
    function launch(): void { if (root.svc) root.svc.launchApp() }
    function quit(): void { if (root.svc) root.svc.quitApp() }
    function save(): void { root.saveCurrent() }
    function volumeUp(): void { if (root.svc) root.svc.nudgeVolume(0.05) }
    function volumeDown(): void { if (root.svc) root.svc.nudgeVolume(-0.05) }
    function repeat(): void { if (root.svc) root.svc.cycleRepeat() }
    function shuffle(): void { if (root.svc) root.svc.toggleShuffle() }
  }

  Row {
    id: body
    anchors.centerIn: parent
    spacing: Style.space(6)

    // Art thumb, or the YouTube glyph when idle.
    Item {
      width: Style.space(18)
      height: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.fill: parent
        radius: Style.space(3)
        color: "transparent"
        border.width: 1
        border.color: root.dimFg
        visible: art.status !== Image.Ready
      }
      Image {
        id: art
        anchors.fill: parent
        source: root.artUrl
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
        // Rounded corners without an OpacityMask: clip to a rounded rect via a
        // layer is heavier than the bar deserves; a 1px inset rect reads the same.
        layer.enabled: false
      }
      // Progress ring around the thumb.
      Canvas {
        id: ring
        anchors.centerIn: parent
        width: parent.width + Style.space(6)
        height: width
        visible: root.hasMedia && !root.vertical
        property real value: root.progress
        onValueChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var c = width / 2, r = c - 1.5
          ctx.lineWidth = 1.5
          ctx.strokeStyle = Qt.rgba(root.dimFg.r, root.dimFg.g, root.dimFg.b, 0.35)
          ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke()
          if (ring.value > 0) {
            ctx.strokeStyle = Color.accent
            ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ring.value); ctx.stroke()
          }
        }
      }
      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        textFormat: Text.PlainText
        text: ""      // Nerd Font: play
        color: root.hasMedia ? root.fg : root.dimFg
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: labelText.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.hasMedia
          ? root.title + (root.artist ? "  ·  " + root.artist : "")
          : "TekTube"
        color: root.hasMedia ? root.fg : root.dimFg
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool needsScroll: implicitWidth > scrollClip.width

        // Marquee only when the label overflows and only while playing: a
        // paused pill sitting still is what tells you it is paused.
        NumberAnimation on x {
          running: labelText.needsScroll && root.isPlaying && !root.opened && !root.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
        Binding {
          target: labelText
          property: "x"
          value: 0
          when: !(labelText.needsScroll && root.isPlaying && !root.opened)
        }
      }
    }
  }

  // Progress hairline along the bottom of the pill.
  Rectangle {
    anchors.bottom: parent.bottom
    anchors.left: body.left
    height: 1
    width: root.hasMedia ? body.width * root.progress : 0
    color: Color.accent
    opacity: root.isPlaying ? 0.9 : 0.5
    visible: root.hasMedia && root.vertical
    Behavior on width { NumberAnimation { duration: 400 } }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (!root.svc) return
      if (mouse.button === Qt.MiddleButton) root.svc.togglePlaying()
      else if (mouse.button === Qt.RightButton) root.svc.next()
      else root.toggle()
    }
    onWheel: function(wheel) {
      if (!root.svc) return
      root.svc.nudgeVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia
      ? root.title + (root.artist ? " — " + root.artist : "")
      : (root.svc && root.svc.app === "ready" ? root.svc.tr("bar.nothingPlaying", "TekTube · nothing playing")
         : root.svc ? root.svc.tr("bar.clickToOpen", "TekTube · click to open") : "TekTube"))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
