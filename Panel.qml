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
  moduleName: "io.github.kelbresqe.plak"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null

  readonly property var barIdentity: hostWidget || root
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property bool ready: svc ? svc.ready : false

  // "home" | "player" | "playlists" | "queue" | "history" | "lyrics" | "search",
  // plus "save" (the save-to-playlist picker, outside the rail and Tab cycle)
  property string view: "player"
  readonly property var views: ["home", "player", "playlists", "queue", "history", "lyrics", "search"]
  property bool viewChosen: false      // until the user picks, follow playback
  property string returnView: "player" // where "save" goes back to

  function show(name) {
    if (root.views.indexOf(name) === -1) return
    root.viewChosen = true
    root.view = name
    if (name === "home" && root.svc && root.svc.home.length === 0) root.svc.loadHome()
    if (name === "lyrics" && root.svc && root.svc.video) root.svc.loadLyrics(root.svc.video)
    if (name === "queue" && root.svc) root.svc.loadQueue()
    if (name === "playlists" && root.svc && root.svc.library.length === 0) root.svc.loadLibrary()
    if (name === "history" && root.svc) root.svc.loadHistory()
  }

  function cycleView(delta) {
    var i = root.views.indexOf(root.view)
    if (i === -1) i = root.views.indexOf(root.returnView)
    root.show(root.views[(i + delta + root.views.length) % root.views.length])
  }

  // Save a track ({videoId, title, artist}) to one of the account's playlists.
  function openSave(track) {
    if (!root.svc || !root.svc.prepareSave(track)) return
    if (root.view !== "save") root.returnView = root.view
    root.view = "save"
  }
  function closeSave() { root.view = root.returnView }

  // e / E / b on whatever track a list view has under its cursor.
  function trackKey(t, track) {
    if (!root.svc || !track || !track.videoId) return false
    if (t === "e") { root.svc.queueAdd(track.videoId, true); return true }
    if (t === "E") { root.svc.queueAdd(track.videoId, false); return true }
    if (t === "b") { root.openSave(track); return true }
    return false
  }
  // The same three as row buttons, for TrackRow.actions.
  readonly property var trackActions: root.svc ? [
    { name: "next", icon: "\u{F0411}", tip: root.svc.tr("actions.playNext", "Play next (e)") },
    { name: "queue", icon: "\u{F0412}", tip: root.svc.tr("actions.addQueue", "Add to queue (E)") },
    { name: "save", icon: "\u{F0CB8}", tip: root.svc.tr("actions.save", "Save to playlist (b)") }
  ] : []
  function trackAction(name, track) {
    root.trackKey(name === "next" ? "e" : name === "queue" ? "E" : name === "save" ? "b" : "", track)
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
    if (t === "i") { root.show("history"); return }
    if (t === "t") { if (root.svc) root.svc.cycleRepeat(); return }
    // Not "x": PanelKeyCatcher turns x / X / Delete into deleteRequested.
    if (t === "m") { if (root.svc) root.svc.toggleShuffle(); return }
    if (t === "b" && root.view === "player" && root.svc && root.svc.video) {
      root.openSave({ videoId: root.svc.video, title: root.svc.title, artist: root.svc.artist }); return
    }
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
      // Ctrl+↑ / Ctrl+↓ and Delete / x, for views that edit a list (the queue).
      reorderable: root.activeView && typeof root.activeView.reorder === "function"
      onReorderRequested: function(direction) { root.activeView.reorder(direction) }
      onDeleteRequested: { if (root.activeView && typeof root.activeView.remove === "function") root.activeView.remove() }

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
                case "history": return Qt.resolvedUrl("views/HistoryView.qml")
                case "save": return Qt.resolvedUrl("views/SaveView.qml")
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
          panel: root
          bar: root.bar
          family: root.family
        }
      }
    }
  }
}
