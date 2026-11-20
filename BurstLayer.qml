import QtQuick

// Shake-off bursts for one monitor: 6 slots of std140 vec4s, rendered by burst.frag.
ShaderEffect {
  id: fx

  required property var svc
  required property string mon
  readonly property real duration: 1.5

  function slotA(i) {
    var b = svc.bursts[i]
    return b && b.mon === mon ? Qt.vector4d(b.x, b.y, b.w, svc.age - b.t0) : Qt.vector4d(0, 0, 0, 0)
  }
  function slotB(i) {
    var b = svc.bursts[i]
    if (!b || b.mon !== mon) return Qt.vector4d(0, 0, 0, 0)
    var age = svc.age - b.t0
    return Qt.vector4d(b.amount, b.wind, b.seed, age >= 0 && age < duration ? 1 : 0)
  }

  readonly property bool live: {
    for (var i = 0; i < 6; i++) if (slotB(i).w > 0.5) return true
    return false
  }
  visible: live
  blending: true

  property real tintMix: svc.tintMix
  property vector2d size: Qt.vector2d(width, height)
  property color tint: svc.tint

  property vector4d bA0: slotA(0)
  property vector4d bA1: slotA(1)
  property vector4d bA2: slotA(2)
  property vector4d bA3: slotA(3)
  property vector4d bA4: slotA(4)
  property vector4d bA5: slotA(5)
  property vector4d bB0: slotB(0)
  property vector4d bB1: slotB(1)
  property vector4d bB2: slotB(2)
  property vector4d bB3: slotB(3)
  property vector4d bB4: slotB(4)
  property vector4d bB5: slotB(5)

  fragmentShader: Qt.resolvedUrl("shaders/burst.frag.qsb")
}
