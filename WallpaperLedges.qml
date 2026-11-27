import QtQuick
import QtQuick.Window
import "ledges.js" as Ledges

// Builds the wallpaper contour map for one screen: loads the current wallpaper once as a small
// thumbnail (one sample per `cell` screen px, read in image pixels so the output scale does not
// matter), crops it the way the Omarchy background covers the screen, and runs ledges.js.
// The map is rebuilt when the wallpaper, screen size or scale changes, and cleared at once.
Canvas {
  id: root
  property string source: ""
  property real screenWidth: 0
  property real screenHeight: 0
  property var ledges: []
  readonly property int cell: 4
  readonly property real outputScale: Screen.devicePixelRatio
  readonly property string url: source && !/\.(mp4|webm|mkv|mov|gif)$/i.test(source)
      ? "file://" + source.split("/").map(encodeURIComponent).join("/") : ""
  property string pending: ""
  width: 1
  height: 1
  opacity: 0

  function invalidate() {
    if (pending) unloadImage(pending)
    pending = ""
    ledges = []
    settle.restart()
  }
  onUrlChanged: invalidate()
  onScreenWidthChanged: invalidate()
  onScreenHeightChanged: invalidate()
  onOutputScaleChanged: invalidate()
  onAvailableChanged: invalidate()
  Timer {
    id: settle
    interval: 100
    onTriggered: {
      if (!root.available || !root.url || root.screenWidth <= 0 || root.screenHeight <= 0) return
      root.pending = root.url
      // One requested dimension preserves the original aspect ratio.
      root.loadImage(root.pending, Qt.size(Math.ceil(root.screenWidth / root.cell), 0))
      if (root.isImageLoaded(root.pending)) root.requestPaint()
    }
  }
  onImageLoaded: if (pending) requestPaint()
  onPaint: {
    if (!pending || !isImageLoaded(pending)) return
    var thumb = getContext("2d").createImageData(pending)
    var w = Math.max(1, Math.round(screenWidth / cell)), h = Math.max(1, Math.round(screenHeight / cell))
    var factor = Math.min(thumb.width / w, thumb.height / h)
    var left = (thumb.width - w * factor) / 2, top = (thumb.height - h * factor) / 2
    var grid = new Uint8Array(4 * w * h), src = thumb.data
    for (var y = 0; y < h; y++) {
      var row = Math.floor(top + (y + 0.5) * factor) * thumb.width
      for (var x = 0; x < w; x++) {
        var i = 4 * (row + Math.floor(left + (x + 0.5) * factor)), j = 4 * (y * w + x)
        grid[j] = src[i]; grid[j+1] = src[i+1]; grid[j+2] = src[i+2]
      }
    }
    unloadImage(pending)
    pending = ""
    ledges = Ledges.detect(grid, w, h, screenWidth / w)
  }
}
