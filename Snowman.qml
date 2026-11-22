import QtQuick

// A little snowman that builds itself on the monitor's snowbank once the bank is full, and
// melts away again when the snow is cleared. Drawn by shaders/snowman.frag (no image assets).
ShaderEffect {
  id: fx

  required property var svc
  property real areaWidth: 0          // monitor width (px)
  property real anchorY: 0            // monitor height: the bank's bottom edge (px)

  readonly property real unitPx: 1.1  // px per model unit
  readonly property real target: (svc.settings.snowman && svc.settings.bottomBank)
                                 ? Math.max(0, Math.min(1, (svc.bank - 0.7) / 0.3)) : 0
  property real prog: target
  Behavior on prog { NumberAnimation { duration: 1400; easing.type: Easing.InOutQuad } }

  // A fresh spot (and nose direction) each time it is rebuilt.
  property real xFrac: 0.12 + 0.76 * Math.random()
  property real flip: Math.random() < 0.5 ? -1 : 1
  property real baseLean: (Math.random() < 0.5 ? -1 : 1) * (0.16 + 0.14 * Math.random())   // ~9-17 degrees
  // Optional swing: eased in and out, a slow pendulum about the base. 1.6 rad/s is a multiple of 0.1,
  // so it stays seamless when the shared sway clock wraps.
  property real swingMix: svc.settings.snowmanSwing ? 1 : 0
  Behavior on swingMix { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
  property real lean: baseLean + swingMix * 0.16 * Math.sin(1.6 * svc.swayTime)
  readonly property real sink: 9      // model units lowered: the base sinks below the bank / screen edge
  onProgChanged: if (prog <= 0.0001) {
    xFrac = 0.12 + 0.76 * Math.random(); flip = Math.random() < 0.5 ? -1 : 1
    baseLean = (Math.random() < 0.5 ? -1 : 1) * (0.16 + 0.14 * Math.random())
  }

  visible: prog > 0.01
  blending: true

  // Hover easter egg: the snowman shrinks away and pops back up somewhere else along the bank.
  property real pop: 1
  readonly property bool ready: prog > 0.9 && pop > 0.99
  opacity: pop
  scale: 0.5 + 0.5 * pop
  transformOrigin: Item.Bottom
  function hop() {
    if (!ready || hopAnim.running) return
    hopAnim.start()
  }
  SequentialAnimation {
    id: hopAnim
    NumberAnimation { target: fx; property: "pop"; to: 0; duration: 130; easing.type: Easing.InQuad }
    ScriptAction { script: {
      var n = xFrac
      for (var i = 0; i < 20 && Math.abs(n - xFrac) < 0.25; i++) n = 0.12 + 0.76 * Math.random()
      xFrac = n
      if (Math.random() < 0.5) flip = -flip
    } }
    PauseAnimation { duration: 120 }
    NumberAnimation { target: fx; property: "pop"; to: 1; duration: 320; easing.type: Easing.OutBack }
  }

  width: 84 * unitPx                 // wide enough for the arms plus the lean
  height: 70 * unitPx
  x: xFrac * Math.max(0, areaWidth - width)
  y: anchorY - 3 - (height - 2 * unitPx) + sink * unitPx   // partly submerged below the bank / screen edge

  property real sway: svc.swayTime
  property real wind: svc.windLean
  property real unit: unitPx
  property real tintMix: svc.tintMix
  property vector2d size: Qt.vector2d(width, height)
  property color tint: svc.tint
  property color shade: svc.shade
  property color scarf: svc.themePalette.colors[0]

  fragmentShader: Qt.resolvedUrl("shaders/snowman.frag.qsb")
}
