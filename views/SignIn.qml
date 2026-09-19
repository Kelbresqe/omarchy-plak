import QtQuick
import qs.Ui
import qs.Commons
import "../Bridge.js" as Bridge

// Shown instead of the views until the bridge reports `ready`.
Column {
  id: root
  property var svc: null
  property string family: Style.font.family
  spacing: Style.space(10)

  readonly property var desc: Bridge.describe(svc ? svc.app : "bridge-down", svc ? svc.link : "down")

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: "TekTube"
    color: Color.foreground
    font.family: root.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }
  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.desc.text
    color: Color.foreground
    opacity: 0.7
    font.family: root.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }
  Text {
    width: parent.width
    visible: svc && svc.app === "signed-out"
    textFormat: Text.PlainText
    text: "Use your normal Google login. The window keeps its own browser profile; this plugin never sees your password or cookies."
    color: Color.foreground
    opacity: 0.45
    font.family: root.family
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }
  Button {
    visible: root.desc.action !== ""
    text: root.desc.action === "launch" ? "Open YouTube Music" : "Show the window"
    bordered: true
    fontFamily: root.family
    onClicked: {
      if (!svc) return
      if (root.desc.action === "launch") svc.launchApp()
      else svc.revealApp()
    }
  }
}
