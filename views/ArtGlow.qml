import QtQuick
import "../Glow.js" as Glow

// Samples an Image at 8×8 and produces one theme-safe colour for the glow
// behind it. Pure maths in Glow.js; this only does the pixel reading.
Item {
  id: root
  property Image source: null
  property color accent: "#888888"
  property color background: "#000000"
  property color color: accent
  visible: false
  width: 8
  height: 8

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    onPaint: {
      if (!root.source || root.source.status !== Image.Ready) return
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.drawImage(root.source, 0, 0, width, height)
      var px
      try { px = ctx.getImageData(0, 0, width, height).data } catch (e) { return }
      var rgb = Glow.dominant(px)
      if (!rgb) { root.color = root.accent; return }
      var mixed = Glow.mix(rgb, [root.accent.r * 255, root.accent.g * 255, root.accent.b * 255],
                           [root.background.r * 255, root.background.g * 255, root.background.b * 255])
      root.color = Qt.rgba(mixed[0] / 255, mixed[1] / 255, mixed[2] / 255, 1)
    }
  }

  Connections {
    target: root.source
    function onStatusChanged() {
      if (root.source.status === Image.Ready) { canvas.unloadImage(root.source.source); canvas.loadImage(root.source.source); canvas.requestPaint() }
      else root.color = root.accent
    }
  }
  Connections {
    target: canvas
    function onImageLoaded() { canvas.requestPaint() }
  }
}
