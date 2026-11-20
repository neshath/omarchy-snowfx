import QtQuick

// Snowdrift for one window (or a monitor's bottom snowbank): a strip above the
// window's top edge, hugging its rounded corners. Height follows the per-window
// accumulation tracked by the service.
ShaderEffect {
  id: fx

  required property var svc
  property var win: null              // {x, y, w, h, occ}; for the bank: the bottom edge line
  property real acc: 0                // accumulation 0..1
  property real radius: 0             // Hyprland decoration:rounding
  property bool bank: false

  readonly property real pad: 6
  readonly property real headroom: 16 // room above the edge for the tallest mound

  visible: win !== null && acc > 0.01 && svc.settings.drifts
  blending: true

  x: win ? win.x - pad : 0
  y: win ? win.y - headroom : 0
  width: win ? win.w + 2 * pad : 0
  height: headroom + radius + 10

  property real level: Math.pow(acc, 0.85)
  // Peak height caps (px): flat window ~3.5-4.5, sculpted ~5.5-7; bank flat ~5-6, sculpted ~7-9.
  readonly property real dens: Math.max(0, Math.min(1, svc.settings.density))
  readonly property bool sculpted: svc.settings.driftStyle === "sculpted"
  property real maxHeight: bank ? (sculpted ? 7 + 2 * dens : 5 + dens)
                                : (sculpted ? 5.5 + 1.5 * dens : 3.5 + dens)
  property real seed: bank ? 0.37 : (win ? ((win.x * 0.013 + win.w * 0.007) % 1) : 0)
  property real tintMix: svc.tintMix
  property real wind: svc.settings.windX
  property real style: sculpted ? 1 : 0
  property real edgeTaper: bank ? 0 : 1
  property vector2d size: Qt.vector2d(width, height)
  property vector4d rect: Qt.vector4d(pad, headroom, win ? win.w : 0, win ? win.h : 0)

  function occAt(i) {
    var o = win && win.occ && win.occ[i]
    return o ? Qt.vector4d(o.x - x, o.y - y, o.w, o.h) : Qt.vector4d(0, 0, 0, 0)
  }
  property vector4d occ0: occAt(0)
  property vector4d occ1: occAt(1)
  property vector4d occ2: occAt(2)
  property vector4d occ3: occAt(3)

  property color tint: svc.tint
  property color shade: svc.shade

  fragmentShader: Qt.resolvedUrl("shaders/drift.frag.qsb")
}
