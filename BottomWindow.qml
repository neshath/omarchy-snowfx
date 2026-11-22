import QtQuick
import Quickshell
import Quickshell.Wayland

// Click-through Bottom layer: parallax snow over the wallpaper, behind every window.
// The surface lives as long as its screen and the `enabled` setting. Nothing else (workspace,
// active window, group tab, fullscreen guard) maps or unmaps it; the guard fades the content.
PanelWindow {
  id: win

  required property var svc
  required property var modelData
  readonly property bool guarded: svc.settledFs[modelData.name] === true

  screen: modelData
  visible: svc.settings.enabled
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "snowfx-snow"
  mask: Region {}

  Item {
    id: stage
    anchors.fill: parent
    opacity: win.guarded ? 0 : 1
    visible: opacity > 0.001
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

    SnowLayer { anchors.fill: parent; svc: win.svc; kind: 0 }
  }
}
