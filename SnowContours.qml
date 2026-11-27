import QtQuick

// Snow lying on the wallpaper contours: a thin, soft strip along each contour that thickens as
// `acc` grows, fuller where the contour is flat and thinner on slopes. Repainted only when the
// contours change or the accumulation has moved noticeably, so it is static once built.
// The canvas covers just the band the contours occupy, not the whole screen.
Canvas {
  id: root

  property var contours: []
  property real acc: 0
  property color tint: "white"
  property color shade: "#506080"
  property real tintMix: 0.16
  property real maxHeight: 5          // px at full accumulation on a flat stretch

  readonly property real pad: maxHeight + 4

  // Per contour, computed once per wallpaper: screen points plus the relative snow height at
  // each point (flatness, end taper, gentle deterministic lumps).
  property var geom: []
  property real drawnAcc: -1

  function hash(n) { var s = Math.sin(n * 91.345) * 47453.5453; return s - Math.floor(s) }
  function css(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }

  function rebuild() {
    var g = [], minY = 1e9, maxY = -1e9
    for (var c = 0; c < contours.length; c++) {
      var p = contours[c].pts, n = p.length / 2
      if (n < 3) continue
      var rel = []
      for (var i = 0; i < n; i++) {
        var i0 = Math.max(0, i - 2), i1 = Math.min(n - 1, i + 2)
        var slope = Math.abs(p[2 * i1 + 1] - p[2 * i0 + 1]) / Math.max(1, p[2 * i1] - p[2 * i0])
        var flat = Math.max(0, 1 - slope)                   // 1 flat .. 0 at 45 degrees
        var taper = Math.min(1, Math.min(i, n - 1 - i) / 8)
        taper = taper * taper * (3 - 2 * taper)
        var lump = 0.8 + 0.4 * (0.5 + 0.5 * Math.sin(i * 0.35 + c * 1.7) * hash(c * 13 + Math.floor(i / 6)))
        rel.push((0.3 + 0.7 * flat) * taper * lump)
        minY = Math.min(minY, p[2 * i + 1]); maxY = Math.max(maxY, p[2 * i + 1])
      }
      g.push({ p: p, rel: rel })
    }
    shed.stop()
    opacity = 1
    geom = g
    // Shrink to the occupied band; an empty map needs no backing store at all.
    y = g.length ? Math.max(0, Math.floor(minY - pad)) : 0
    height = g.length ? Math.ceil(maxY - minY + 2 * pad) : 0
    requestPaint()
  }

  onContoursChanged: rebuild()
  onAccChanged: {
    if (acc === 0 && drawnAcc > 0.05 && geom.length) { if (!shed.running) shed.start(); return }   // shaken off
    if (shed.running && acc < 0.05) return            // fresh buildup must not cut the fade short
    if (Math.abs(acc - drawnAcc) > 0.015 || (acc === 0) !== (drawnAcc === 0)) { shed.stop(); opacity = 1; requestPaint() }
  }
  onWidthChanged: requestPaint()

  // Shake: the settled snow fades away quickly instead of vanishing in one frame.
  SequentialAnimation {
    id: shed
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InQuad }
    ScriptAction { script: { root.requestPaint(); root.opacity = 1 } }
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    drawnAcc = acc
    if (acc < 0.01 || !geom.length) return

    var snow = Qt.rgba(1 - (1 - tint.r) * tintMix, 1 - (1 - tint.g) * tintMix, 1 - (1 - tint.b) * tintMix, 1)
    var level = Math.pow(acc, 0.85)
    var show = Math.min(1, level * 4)                  // fade in: no instant line on a fresh wallpaper
    var oy = y                                         // contours are in screen px; the canvas starts at y
    var shadowCss = css(shade, 0.28 * level), snowCss = css(snow, 0.92 * show)
    var rimCss = "rgba(255,255,255," + (0.9 * show) + ")"

    for (var c = 0; c < geom.length; c++) {
      var p = geom[c].p, rel = geom[c].rel, n = rel.length
      var top = []
      for (var i = 0; i < n; i++) top.push(p[2 * i], p[2 * i + 1] - oy - maxHeight * level * rel[i])

      // Contact shadow just under the snow.
      ctx.beginPath()
      ctx.moveTo(p[0], p[1] - oy + 1)
      for (i = 1; i < n; i++) ctx.lineTo(p[2 * i], p[2 * i + 1] - oy + 1)
      ctx.lineWidth = 2
      ctx.strokeStyle = shadowCss
      ctx.stroke()

      // Snow body: smooth top (quadratic through midpoints), straight back along the contour.
      ctx.beginPath()
      ctx.moveTo(top[0], top[1])
      for (i = 1; i < n - 1; i++)
        ctx.quadraticCurveTo(top[2 * i], top[2 * i + 1], (top[2 * i] + top[2 * i + 2]) / 2, (top[2 * i + 1] + top[2 * i + 3]) / 2)
      ctx.lineTo(top[2 * n - 2], top[2 * n - 1])
      for (i = n - 1; i >= 0; i--) ctx.lineTo(p[2 * i], p[2 * i + 1] - oy + 0.5)
      ctx.closePath()
      ctx.fillStyle = snowCss
      ctx.fill()

      // Bright rim along the top.
      ctx.beginPath()
      ctx.moveTo(top[0], top[1])
      for (i = 1; i < n - 1; i++)
        ctx.quadraticCurveTo(top[2 * i], top[2 * i + 1], (top[2 * i] + top[2 * i + 2]) / 2, (top[2 * i + 1] + top[2 * i + 3]) / 2)
      ctx.lineWidth = 1
      ctx.strokeStyle = rimCss
      ctx.stroke()
    }
  }
}
