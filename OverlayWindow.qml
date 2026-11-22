import QtQuick
import Quickshell
import Quickshell.Wayland

// Click-through Overlay layer: snowdrifts resting on visible window top edges,
// plus a sparse layer of soft foreground bokeh flakes.
// Like BottomWindow, the surface is only tied to its screen and `enabled`; the fullscreen
// guard fades the content.
PanelWindow {
  id: ow

  required property var svc
  required property var modelData
  readonly property var info: svc.tracker.screens[modelData.name] || null
  readonly property bool guarded: svc.settledFs[modelData.name] === true
  readonly property real rounding: info ? info.rounding : 0

  // Stable per-window delegates (keyed by Hyprland address). A delegate exists for every
  // window the service still caches on this monitor, visible or not: hidden ones (other
  // workspace / inactive tab) fade out in place instead of being destroyed, so settled snow
  // survives switches and only goes away when the window really closes.
  property var byAddr: ({})                   // addr -> visible window rect on this monitor
  ListModel { id: addrs }

  function sync() {
    var map = {}
    var list = info && svc.settings.drifts ? info.windows : []
    for (var i = 0; i < list.length; i++) if (list[i].addr && list[i].w > 40) map[list[i].addr] = list[i]
    var want = {}
    for (var a in svc.reg) if (svc.reg[a].mon === modelData.name && svc.reg[a].w > 40) want[a] = true
    for (var m in map) want[m] = true
    for (var k = addrs.count - 1; k >= 0; k--) if (!want[addrs.get(k).addr]) addrs.remove(k)
    var have = {}
    for (var j = 0; j < addrs.count; j++) have[addrs.get(j).addr] = true
    for (var w in want) if (!have[w]) addrs.append({ addr: w })
    byAddr = map
  }
  onInfoChanged: sync()
  Connections { target: svc; function onRegChanged() { ow.sync() } }
  Connections { target: svc.settings; function onDriftsChanged() { ow.sync() } }
  Component.onCompleted: sync()

  screen: modelData
  visible: svc.settings.enabled
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "snowfx-drifts"
  mask: Region { item: snowHit }

  Item {
    id: stage
    anchors.fill: parent
    opacity: ow.guarded ? 0 : 1
    visible: opacity > 0.001
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

    Repeater {
      model: addrs
      DriftRect {
        required property string addr
        svc: ow.svc
        win: ow.byAddr[addr] || null
        acc: ow.svc.accum[addr] || 0
        radius: ow.rounding
        mon: ow.modelData.name
        waddr: addr
      }
    }

    // Thin snowbank along the bottom edge of this monitor.
    DriftRect {
      svc: ow.svc
      bank: true
      win: svc.settings.bottomBank && ow.width > 0 ? ({ x: 0, y: ow.height, w: ow.width, h: 0, occ: [] }) : null
      acc: svc.bank
    }

    // Easter egg: a snowman that builds itself on the bank once it is full.
    Snowman { id: snowman; svc: ow.svc; areaWidth: ow.width; anchorY: ow.height }

    // The only part of this surface that takes input: the built snowman. Hovering it makes it hop.
    Item {
      id: snowHit
      x: snowman.x; y: snowman.y
      width: snowman.ready ? snowman.width : 0
      height: snowman.ready ? snowman.height : 0
      HoverHandler { onHoveredChanged: if (hovered) snowman.hop() }
    }

    BurstLayer { anchors.fill: parent; svc: ow.svc; mon: ow.modelData.name }

    SnowLayer { anchors.fill: parent; svc: ow.svc; kind: 1 }
  }
}
