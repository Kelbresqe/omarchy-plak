import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Bridge.js" as Bridge
import "views" as Views

// The popup: a rail of views on the left, the active view, and the transport
// bar underneath. All state lives in the service; this only renders and
// routes keys.
Panel {
  id: root
  moduleName: "tiertek.ytm"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null

  readonly property var barIdentity: hostWidget || root
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool ready: svc ? svc.ready : false

  // "home" | "player" | "playlists" | "queue" | "lyrics" | "search"
  property string view: "player"
  readonly property var views: ["home", "player", "playlists", "queue", "lyrics", "search"]
  property bool viewChosen: false      // until the user picks, follow playback

  function show(name) {
    if (root.views.indexOf(name) === -1) return
    root.viewChosen = true
    root.view = name
    if (name === "home" && root.svc && root.svc.home.length === 0) root.svc.loadHome()
    if (name === "lyrics" && root.svc && root.svc.video) root.svc.loadLyrics(root.svc.video)
    if (name === "queue" && root.svc) root.svc.loadQueue()
    if (name === "playlists" && root.svc && root.svc.library.length === 0) root.svc.loadLibrary()
  }

  function cycleView(delta) {
    var i = root.views.indexOf(root.view)
    root.show(root.views[(i + delta + root.views.length) % root.views.length])
  }

  onOpenedChanged: {
    if (!opened) return
    // Nothing playing yet: open on Home, where the mixes are.
    if (!root.viewChosen && root.svc && !root.svc.hasMedia) root.view = "home"
    if (root.view === "lyrics" && root.svc && root.svc.video) root.svc.loadLyrics(root.svc.video)
    if (root.view === "queue" && root.svc) root.svc.loadQueue()
  }

  // Lyrics follow the track while the panel is open on them.
  Connections {
    target: root.svc
    function onTrackChanged(video) {
      if (root.opened && root.view === "lyrics") root.svc.loadLyrics(video)
    }
  }

  readonly property var activeView: viewLoader.item

  function textKey(t) {
    if (t === "/") { root.show("search"); if (root.activeView && root.activeView.focusInput) root.activeView.focusInput(); return }
    if (t === "p") { root.show("playlists"); return }
    if (t === "h") { root.show("home"); return }
    if (t === "q") { root.show("queue"); return }
    if (t === "y") { root.show("lyrics"); return }
    if (t === "n") { root.show("player"); return }
    if (t === "f") { if (root.svc) root.svc.toggleLike(); return }
    if (t === "d") { if (root.svc) root.svc.dislike(); return }
    if (t === "r") { if (root.svc && root.svc.video) root.svc.radio(root.svc.video); return }
    if (t === "t") { if (root.svc) root.svc.cycleRepeat(); return }
    if (t === "x") { if (root.svc) root.svc.toggleShuffle(); return }
    if (t === ",") { if (root.svc) root.svc.previous(); return }
    if (t === ".") { if (root.svc) root.svc.next(); return }
    if (root.activeView && root.activeView.textKey) root.activeView.textKey(t)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(layout.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: root.activeView && root.activeView.inputActive === true
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cycleView(direction) }
      onMoveRequested: function(dx, dy) { if (root.activeView && root.activeView.move) root.activeView.move(dx, dy) }
      onActivateRequested: {
        if (root.activeView && root.activeView.activate) root.activeView.activate()
        else if (root.svc) root.svc.togglePlaying()
      }
      onTextKey: function(t) { root.textKey(t) }

      // Blurred album art behind everything, only while the panel is open.
      Loader {
        anchors.fill: parent
        anchors.margins: -panel.padding
        z: -1
        active: root.opened && root.svc && root.svc.artUrl !== ""
        sourceComponent: Views.Ambient { svc: root.svc }
      }

      Column {
        id: layout
        anchors.fill: parent
        spacing: Style.space(10)

        Views.Header {
          width: parent.width
          svc: root.svc
          family: root.family
        }

        // Not signed in / not running: one line and the one button that fixes it.
        Loader {
          width: parent.width
          active: !root.ready
          visible: active
          sourceComponent: Views.SignIn {
            svc: root.svc
            family: root.family
            width: layout.width
          }
        }

        Row {
          width: parent.width
          height: root.ready ? Style.space(320) : 0
          visible: root.ready
          spacing: Style.space(10)

          Views.Rail {
            id: rail
            height: parent.height
            family: root.family
            current: root.view
            onSelected: function(name) { root.show(name) }
          }

          Loader {
            id: viewLoader
            width: parent.width - rail.width - Style.space(10)
            height: parent.height
            active: root.ready
            source: {
              switch (root.view) {
                case "home": return Qt.resolvedUrl("views/HomeView.qml")
                case "playlists": return Qt.resolvedUrl("views/PlaylistsView.qml")
                case "queue": return Qt.resolvedUrl("views/QueueView.qml")
                case "lyrics": return Qt.resolvedUrl("views/LyricsView.qml")
                case "search": return Qt.resolvedUrl("views/SearchView.qml")
                default: return Qt.resolvedUrl("views/PlayerView.qml")
              }
            }
            onLoaded: {
              item.svc = root.svc
              item.panel = root
              item.family = root.family
            }
          }
        }

        Views.Transport {
          width: parent.width
          visible: root.ready || (root.svc && root.svc.hasMedia)
          svc: root.svc
          bar: root.bar
          family: root.family
        }
      }
    }
  }
}
