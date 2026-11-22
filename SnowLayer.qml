import QtQuick

// One full-monitor particle stack. kind 0: six depth planes behind windows. kind 1: foreground layer.
// Motion comes from integrated phases (see Service.qml), never from time * speed in the shader.
ShaderEffect {
  id: fx

  required property var svc
  property real kind: 0

  blending: true

  readonly property var offs: kind < 0.5 ? svc.offs0 : svc.offs1

  property real sway: svc.swayTime
  property real amount: svc.amountEased
  property real psize: svc.sizeEased
  property real tintMix: svc.tintMix
  property vector2d size: Qt.vector2d(width, height)
  property vector4d o0: offs[0]
  property vector4d o1: offs[1]
  property vector4d o2: offs[2]
  property vector4d o3: offs[3]
  property vector4d o4: offs[4]
  property vector4d o5: offs[5]
  property color tint: svc.tint

  fragmentShader: Qt.resolvedUrl("shaders/snow.frag.qsb")
}
