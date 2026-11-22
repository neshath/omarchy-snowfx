import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Event-driven window/monitor geometry. Listens to Hyprland raw events,
// debounces, then queries hyprctl once (monitors + clients + rounding).
Item {
  id: root
  visible: false

  property bool active: true
  property bool pollWindows: false     // resizes while dragging emit no event
  property var screens: ({})           // monitor name -> {w, h, rounding, fullscreen, windows[]}
  property var alive: ({})             // address -> {ws, hidden} for every mapped client (any workspace / tab)

  readonly property var watched: ({
    openwindow: 1, closewindow: 1, movewindow: 1, movewindowv2: 1, resizewindow: 1,
    changefloatingmode: 1, workspace: 1, workspacev2: 1, focusedmon: 1, focusedmonv2: 1,
    activewindow: 1, activewindowv2: 1, fullscreen: 1, monitoradded: 1, monitorremoved: 1,
    configreloaded: 1, movewindowv3: 1, pin: 1, activespecial: 1,
    changegroupactive: 1, togglegroup: 1, moveintogroup: 1, moveoutofgroup: 1
  })
  property bool queued: false
  property int seqStarted: 0           // queries started so far
  property int seqParsed: 0            // sequence number of the snapshot behind `screens`
  property int inflightSeq: 0

  function refresh() { if (active) debounce.restart() }
  onActiveChanged: if (active) refresh()

  function query() {
    if (!active) return
    if (proc.running) { queued = true; return }
    seqStarted++
    inflightSeq = seqStarted
    proc.running = true
  }

  function parse(text) {
    var parts = String(text).split("\n@@\n")
    if (parts.length < 3) return
    var mons, cls, rnd = 0
    try {
      mons = JSON.parse(parts[0]); cls = JSON.parse(parts[1])
      var opt = JSON.parse(parts[2]); rnd = Number(opt.int !== undefined ? opt.int : opt.float) || 0
    } catch (e) { return }

    var live = {}
    for (var q = 0; q < cls.length; q++) if (cls[q].mapped) live[String(cls[q].address)] = { ws: cls[q].workspace.id, hidden: !!cls[q].hidden }

    var out = {}
    for (var i = 0; i < mons.length; i++) {
      var m = mons[i]
      var scale = m.scale > 0 ? m.scale : 1
      var wsId = m.specialWorkspace && m.specialWorkspace.id !== 0 ? m.specialWorkspace.id : m.activeWorkspace.id
      var wins = [], fullscreen = false
      for (var k = 0; k < cls.length; k++) {
        var c = cls[k]
        if (!c.mapped || c.hidden || c.monitor !== m.id) continue
        if (c.workspace.id !== wsId && !c.pinned) continue
        if (c.fullscreen > 0) fullscreen = true
        wins.push({ addr: String(c.address), ws: c.workspace.id, x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1],
          floating: !!c.floating, focused: c.focusHistoryID === 0,
          // Stacking = position in Hyprland's client list (later = on top). Focus history is NOT the
          // stacking order: focusing a floating window does not raise it.
          z: (c.fullscreen > 0 ? 200000 : (c.floating ? 100000 : 0)) + k })
      }
      wins.sort(function(a, b) { return a.z - b.z })
      for (var a = 0; a < wins.length; a++) {
        var occ = []
        for (var b = wins.length - 1; b > a && occ.length < 4; b--) {
          var u = wins[b], v = wins[a]
          if (u.x < v.x + v.w + 40 && u.x + u.w > v.x - 40 && u.y < v.y + v.h + 40 && u.y + u.h > v.y - 40) occ.push(u)
        }
        wins[a].occ = occ
      }
      out[m.name] = { w: m.width / scale, h: m.height / scale, rounding: rnd, fullscreen: fullscreen, windows: wins }
    }
    root.seqParsed = root.inflightSeq
    root.alive = live            // before screens: listeners of screensChanged read it
    root.screens = out
  }

  Connections {
    target: Hyprland
    enabled: root.active
    function onRawEvent(event) { if (root.watched[event.name]) root.refresh() }
  }

  Timer { id: debounce; interval: 32; onTriggered: root.query() }
  Timer { interval: 1000; repeat: true; running: root.active && root.pollWindows; onTriggered: root.query() }

  Process {
    id: proc
    command: ["sh", "-c", "hyprctl -j monitors; printf '\\n@@\\n'; hyprctl -j clients; printf '\\n@@\\n'; hyprctl -j getoption decoration:rounding"]
    stdout: StdioCollector { onStreamFinished: root.parse(text) }
    onRunningChanged: if (!running && root.queued) { root.queued = false; root.query() }
  }

  Component.onCompleted: refresh()
  Component.onDestruction: { debounce.stop(); proc.running = false }
}
