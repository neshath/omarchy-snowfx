import QtQuick
import Quickshell
import Quickshell.Wayland

// Click-through Overlay layer: snowdrifts resting on visible window top edges,
// plus a sparse layer of soft foreground bokeh flakes.
PanelWindow {
  id: ow

  required property var svc
  required property var modelData
  readonly property var info: svc.tracker.screens[modelData.name] || null
  readonly property bool guarded: info ? info.fullscreen : false
  readonly property real rounding: info ? info.rounding : 0

  // Stable per-window delegates (keyed by Hyprland address) so settled snow
  // survives focus changes and tracker refreshes, and only resets on real change.
  property var byAddr: ({})
  ListModel { id: addrs }

  function sync() {
    var map = {}
    var list = info && svc.settings.drifts ? info.windows : []
    for (var i = 0; i < list.length; i++) if (list[i].addr && list[i].w > 40) map[list[i].addr] = list[i]
    for (var k = addrs.count - 1; k >= 0; k--) if (!map[addrs.get(k).addr]) addrs.remove(k)
    var have = {}
    for (var j = 0; j < addrs.count; j++) have[addrs.get(j).addr] = true
    for (var a in map) if (!have[a]) addrs.append({ addr: a })
    byAddr = map
  }
  onInfoChanged: sync()
  Connections { target: svc.settings; function onDriftsChanged() { ow.sync() } }
  Component.onCompleted: sync()

  screen: modelData
  visible: svc.settings.enabled && !guarded
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "snowfx-drifts"
  mask: Region {}

  Repeater {
    model: addrs
    DriftRect {
      required property string addr
      svc: ow.svc
      win: ow.byAddr[addr] || null
      acc: ow.svc.accum[addr] || 0
      radius: ow.rounding
    }
  }

  // Thin snowbank along the bottom edge of this monitor.
  DriftRect {
    svc: ow.svc
    bank: true
    win: svc.settings.bottomBank && ow.width > 0 ? ({ x: 0, y: ow.height, w: ow.width, h: 0, occ: [] }) : null
    acc: svc.bank
  }

  BurstLayer { anchors.fill: parent; svc: ow.svc; mon: ow.modelData.name }

  SnowLayer { anchors.fill: parent; svc: ow.svc; kind: 1 }
}
