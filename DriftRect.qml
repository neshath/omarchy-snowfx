import QtQuick

// Snowdrift for one window (or a monitor's bottom snowbank): a strip above the
// window's top edge, hugging its rounded corners. Height follows the per-window
// accumulation tracked by the service.
ShaderEffect {
  id: fx

  required property var svc
  property var win: null              // {x, y, w, h, occ} while shown; for the bank: the bottom edge line
  property real acc: 0                // accumulation 0..1
  property real radius: 0             // Hyprland decoration:rounding
  property bool bank: false
  property string mon: ""              // monitor this drift lives on (for the switch hold)
  property string waddr: ""            // Hyprland address (window drifts only)

  readonly property real pad: 6
  readonly property real headroom: 16 // room above the edge for the tallest mound

  // `win` goes null when the window is hidden (other workspace / inactive tab) or drifts are
  // off. The last rect is kept so the snow can fade back in on return; the cached
  // accumulation is untouched.
  property var held: null
  onWinChanged: if (win) held = win
  readonly property bool shown: win !== null
  // Window drifts vanish instantly when hidden or held (no lingering after-image while windows
  // slide away) and fade in over 100 ms when they come back. The bank ignores the hold.
  // During a switch on this monitor the service predicts visibility from cached state so the snow
  // shows on the same frame as its window; the next tracker snapshot confirms or corrects it.
  readonly property bool holding: !bank && (svc.driftHoldMon === "*" || svc.driftHoldMon === mon)
  readonly property bool lit: bank ? shown : (holding ? svc.predictShown(waddr) : shown)
  // Hiding is a plain assignment (a zero-length Behavior still waits for the next animation
  // tick, costing a frame or two of after-image); only fading in is animated.
  property real fade: 0
  opacity: lit ? fade : 0
  onLitChanged: {
    if (lit) {
      // Right after a workspace / tab switch the snow must arrive with its window: no fade.
      if (Date.now() - svc.lastSwitchMs < 700) { fadeIn.stop(); fade = 1 }
      else fadeIn.restart()
    }
    else { fadeIn.stop(); fade = 0 }
  }
  Component.onCompleted: { if (win) held = win; if (lit) fadeIn.start() }
  NumberAnimation { id: fadeIn; target: fx; property: "fade"; from: 0; to: 1; duration: 100; easing.type: Easing.InOutQuad }

  visible: held !== null && acc > 0.01 && opacity > 0.003
  blending: true

  x: held ? held.x - pad : 0
  y: held ? held.y - headroom : 0
  width: held ? held.w + 2 * pad : 0
  height: headroom + radius + 10

  property real level: Math.pow(acc, 0.85)
  // Peak height caps (px): flat window ~3.5-4.5, sculpted ~5.5-7; bank flat ~5-6, sculpted ~7-9.
  readonly property real dens: Math.max(0, Math.min(1, svc.settings.density))
  readonly property bool sculpted: svc.settings.driftStyle === "sculpted"
  property real maxHeight: bank ? (sculpted ? 7 + 2 * dens : 5 + dens)
                                : (sculpted ? 5.5 + 1.5 * dens : 3.5 + dens)
  property real seed: bank ? 0.37 : (held ? ((held.x * 0.013 + held.w * 0.007) % 1) : 0)
  property real tintMix: svc.tintMix
  property real wind: svc.windLean
  property real style: sculpted ? 1 : 0
  property real edgeTaper: bank ? 0 : 1
  property vector2d size: Qt.vector2d(width, height)
  property vector4d rect: Qt.vector4d(pad, headroom, held ? held.w : 0, held ? held.h : 0)

  function occAt(i) {
    var o = held && held.occ && held.occ[i]
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
