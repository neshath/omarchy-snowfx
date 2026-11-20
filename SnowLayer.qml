import QtQuick

// One full-monitor particle stack. kind 0: six depth planes behind windows. kind 1: foreground layer.
ShaderEffect {
  id: fx

  required property var svc
  property real kind: 0

  blending: true

  property real time: svc.time
  property real amount: svc.settings.particleAmount
  property real psize: svc.settings.particleSize
  property real tintMix: svc.tintMix
  property vector2d size: Qt.vector2d(width, height)
  property vector2d scroll: svc.scroll
  property color tint: svc.tint

  fragmentShader: Qt.resolvedUrl("shaders/snow.frag.qsb")
}
