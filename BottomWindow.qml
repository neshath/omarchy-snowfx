import QtQuick
import Quickshell
import Quickshell.Wayland

// Click-through Bottom layer: parallax snow over the wallpaper, behind every window.
PanelWindow {
  id: win

  required property var svc
  required property var modelData
  readonly property var info: svc.tracker.screens[modelData.name] || null
  readonly property bool guarded: info ? info.fullscreen : false

  screen: modelData
  visible: svc.settings.enabled && !guarded
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "snowfx-snow"
  mask: Region {}

  SnowLayer { anchors.fill: parent; svc: win.svc; kind: 0 }
}
