import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// Always-on SnowFx service: per monitor, one click-through Bottom layer (falling
// snow behind windows) and one click-through Overlay layer (snowdrifts, shake-off
// bursts, bottom snowbank and bokeh). One clock drives everything and stops at 0 FPS
// when snow is disabled or every monitor has a fullscreen window.
//
// Continuity rules (no visible reload when switching workspaces / tabs):
//  * Flake motion is two monotonically integrated phases (windPhase, fallPhase) fed by
//    exponentially eased speeds; nothing multiplies elapsed time by a changing speed.
//  * Layer surfaces are bound to Quickshell.screens and `enabled` only; the fullscreen
//    guard is debounced and fades content instead of unmapping surfaces.
//  * Per-window snow is cached by address and only pruned on a real closewindow.
Item {
  id: root
  property var shell: null

  readonly property alias settings: store
  readonly property alias themePalette: paletteModel
  readonly property alias tracker: tracker

  // ---- integrated animation state ------------------------------------------
  // JS doubles, never wrapped: float32 only ever sees the per-pass lattice offsets below.
  property real windPhase: 0                  // px travelled east at parallax 1
  property real fallPhase: 0                  // px travelled down at parallax 1
  property real swayTime: 0                   // flake sway clock, wrapped on a seamless period
  readonly property real swayPeriod: 20 * Math.PI * 60   // sway rates are multiples of 0.1 rad/s
  property real age: 0                        // monotonic; freezes while the clock is stopped
  property real lastTick: 0

  // Eased drivers (exponential smoothing in the tick, so no input ever steps a speed).
  property real effectiveWind: 0              // -2..2, eases toward baseWind + gustImpulse
  property real effectiveFall: 55             // px/s
  property real windLean: 0                   // eased base wind, shapes sculpted drifts
  property real amountEased: store.particleAmount
  property real sizeEased: store.particleSize

  // Gust: a target held for a moment, then released; gustImpulse eases toward it.
  property real gustImpulse: 0
  property real gustDir: 1
  property real gustAmp: 0.3
  property real gustUntil: -1                 // in `age` seconds

  // Per-pass lattice offsets (cells, reduced modulo `lattice`), consumed by snow.frag.
  readonly property real lattice: 1024        // must match LATTICE in shaders/snow.frag
  // Keep in sync with the plane tables in shaders/snow.frag. Second pass: cell * 1.17, ang + 0.9.
  readonly property var planes0: [
    { cell: 12, par: 0.28, ang: 0.31 }, { cell: 18, par: 0.42, ang: 0.83 },
    { cell: 28, par: 0.60, ang: 1.21 }, { cell: 42, par: 0.80, ang: 1.77 },
    { cell: 64, par: 1.10, ang: 0.59 }, { cell: 96, par: 1.45, ang: 2.10 } ]
  readonly property var planes1: [
    { cell: 100, par: 1.80, ang: 1.43 }, { cell: 180, par: 2.20, ang: 0.57 } ]
  property var offs0: [Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0),
                       Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0)]
  property var offs1: [Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0),
                       Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0)]

  function passOffset(cell, par, ang) {
    var sx = root.windPhase * par, sy = root.fallPhase * par
    var ca = Math.cos(ang), sa = Math.sin(ang)
    var x = (ca * sx + sa * sy) / cell, y = (-sa * sx + ca * sy) / cell
    return [x - root.lattice * Math.floor(x / root.lattice), y - root.lattice * Math.floor(y / root.lattice)]
  }
  function offsetsFor(planes) {
    var out = []
    for (var i = 0; i < 6; i++) {
      if (i >= planes.length) { out.push(Qt.vector4d(0, 0, 0, 0)); continue }
      var pl = planes[i]
      var m = passOffset(pl.cell, pl.par, pl.ang)
      var s = passOffset(pl.cell * 1.17, pl.par, pl.ang + 0.9)
      out.push(Qt.vector4d(m[0], m[1], s[0], s[1]))
    }
    return out
  }
  function updateOffsets() {
    root.offs0 = offsetsFor(root.planes0)
    root.offs1 = offsetsFor(root.planes1)
  }

  // Per-window accumulation 0..1, keyed by Hyprland address. Cached across workspace / tab
  // switches; only closewindow (or the client disappearing) prunes an entry.
  property var accum: ({})
  property var reg: ({})                      // addr -> {a, x, y, w, h, mon, vis}
  property var pendingClose: ({})             // addrs named by a closewindow event
  property real bank: 0                       // bottom snowbank 0..1

  // Shake-off bursts: fixed ring of 6 slots {mon, x, y, w, amount, wind, seed, t0}.
  readonly property int burstSlots: 6
  property var bursts: [null, null, null, null, null, null]
  property int burstHead: 0

  readonly property color tint: paletteModel.colors[1]
  readonly property color shade: paletteModel.colors[0]
  readonly property real tintMix: 0.16

  // Fullscreen guard, debounced 150 ms so transient states during a workspace switch never
  // reach the layers. Layers fade on this; they are never unmapped by it.
  property var settledFs: ({})
  property var latestFs: ({})
  function fsMap() {
    var m = {}, s = tracker.screens
    for (var n in s) m[n] = !!s[n].fullscreen
    return m
  }
  function sameFs(a, b) {
    for (var k in a) if (!!a[k] !== !!b[k]) return false
    for (var j in b) if (!!a[j] !== !!b[j]) return false
    return true
  }
  function noteFullscreen() {
    root.latestFs = fsMap()
    if (sameFs(root.latestFs, root.settledFs)) guardTimer.stop()
    else if (!guardTimer.running) guardTimer.start()
  }
  Timer { id: guardTimer; interval: 150; onTriggered: root.settledFs = root.latestFs }

  // A monitor is lit unless snow is off or a (settled) fullscreen window covers it.
  readonly property bool anyLit: {
    if (!store.enabled) return false
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (!settledFs[Quickshell.screens[i].name]) return true
    return false
  }

  SettingsStore { id: store }
  ThemePalette { id: paletteModel }
  HyprTracker {
    id: tracker
    active: store.enabled
    // 1 s fallback poll (resizes emit no event) only while drifts are drawn and a monitor is lit.
    pollWindows: store.enabled && store.drifts && root.anyLit
  }

  // Surfaces live exactly as long as their screen; see BottomWindow / OverlayWindow.
  Variants {
    model: Quickshell.screens
    BottomWindow { svc: root }
  }
  Variants {
    model: Quickshell.screens
    OverlayWindow { svc: root }
  }

  // ---- bursts ------------------------------------------------------------
  function emitBurst(mon, x, y, w, amount, wind) {
    if (!store.drifts || w < 20 || amount < 0.03) return
    var b = root.bursts.slice()
    b[root.burstHead] = { mon: mon, x: x, y: y, w: w, amount: Math.min(1, amount),
      wind: Math.max(-2, Math.min(2, wind)), seed: Math.random() * 100, t0: root.age }
    root.burstHead = (root.burstHead + 1) % root.burstSlots
    root.bursts = b
  }

  // Gentle, eased gust: the target is held for `hold` seconds then released; the eased
  // gustImpulse (and effectiveWind behind it) never steps, even when gusts overlap.
  function startGust(dir, amp, hold) {
    root.gustDir = dir
    root.gustAmp = amp
    root.gustUntil = root.age + (hold === undefined ? 0.7 : hold)
  }

  // ---- window accumulation / shed / close detection ------------------------
  function syncWindows() {
    var cur = {}
    var s = tracker.screens
    for (var name in s) {
      var ws = s[name].windows
      for (var i = 0; i < ws.length; i++)
        if (ws[i].addr) cur[ws[i].addr] = { x: ws[i].x, y: ws[i].y, w: ws[i].w, h: ws[i].h, mon: name, ws: ws[i].ws }
    }
    var alive = tracker.alive
    var next = {}

    // Entries not currently visible stay cached (workspace switch, group tab, special workspace).
    // They are pruned only when Hyprland reported closewindow or the client no longer exists.
    for (var addr in root.reg) {
      if (cur[addr]) continue
      var o0 = root.reg[addr]
      if (root.pendingClose[addr] || !alive[addr]) {
        // Genuine close: visible windows shed their snow; hidden ones just disappear.
        if (root.pendingClose[addr] && o0.vis && o0.a > 0.05)
          root.emitBurst(o0.mon, o0.x, o0.y, o0.w, o0.a, root.effectiveWind)
        continue
      }
      o0.vis = false
      next[addr] = o0
    }

    for (var a in cur) {
      var c = cur[a], o = root.reg[a]
      if (!o) { next[a] = { a: 0, x: c.x, y: c.y, w: c.w, h: c.h, mon: c.mon, vis: true, ws: c.ws, ghid: false }; continue }
      if (!o.vis) {
        // Back from a hidden workspace / tab: adopt geometry silently, keep the cached snow.
        o.x = c.x; o.y = c.y; o.w = c.w; o.mon = c.mon; o.vis = true
      } else {
        var jump = Math.abs(c.x - o.x) > 24 || Math.abs(c.y - o.y) > 24 || Math.abs(c.w - o.w) > 24 || c.mon !== o.mon
        if (jump) {
          var amt = o.a * (0.35 + 0.2 * Math.random())    // drag-to-shake: shed 35-55%
          if (o.a > 0.05) root.emitBurst(o.mon, o.x, o.y, o.w, amt * 0.7, root.effectiveWind)
          o.a -= amt
          o.x = c.x; o.y = c.y; o.w = c.w; o.mon = c.mon
        }
      }
      o.h = c.h
      next[a] = o
    }

    // Keep workspace / group-tab info fresh for every cached window (used to predict visibility).
    for (var ka in next) { var al = alive[ka]; if (al) { next[ka].ws = al.ws; next[ka].ghid = al.hidden } }

    // Close markers are consumed once their window is gone; keep those still waiting for the tracker.
    for (var k in root.pendingClose) if (!next[k]) delete root.pendingClose[k]
    root.reg = next
    publishAccum()
  }

  function publishAccum() {
    var out = {}
    for (var a in root.reg) out[a] = root.reg[a].a
    root.accum = out
  }

  Connections {
    target: tracker
    function onScreensChanged() {
      root.syncWindows(); root.noteFullscreen()
      if (root.driftHoldMon !== "" && tracker.seqParsed >= root.holdTarget) root.releaseHold()
    }
  }

  // Drifts on the switching monitor are hidden the instant a workspace / tab event arrives (the
  // tracker needs ~50-100 ms to catch up, which would leave the old snowline hanging over the
  // sliding windows). The hold ends as soon as the tracker delivers a snapshot taken after the
  // event (fallback timer if none arrives). Flakes and the bank are never affected.
  property string driftHoldMon: ""            // "" = no hold, "*" = every monitor
  property int holdWs: -1                     // workspace being switched to (workspacev2), -1 = unknown
  property string holdGrp: ""                // address that became the active tab (changegroupactive)
  property double lastSwitchMs: 0
  property int holdTarget: 0
  // While a switch is pending, decide from cached state (no tracker round trip) whether a cached
  // window will be visible, so its snow appears on the same frame as the window.
  function predictShown(addr) {
    var o = root.reg[addr]
    if (!o) return false
    if (root.holdGrp !== "") {
      var t = root.reg[root.holdGrp]
      if (!t) return o.vis
      if (addr === root.holdGrp) return true
      if (o.ws === t.ws && Math.abs(o.x - t.x) < 3 && Math.abs(o.y - t.y) < 3 && Math.abs(o.w - t.w) < 3) return false
      return o.vis
    }
    if (root.holdWs >= 0) return o.ws === root.holdWs && !o.ghid
    return false
  }
  function releaseHold() { root.driftHoldMon = ""; holdTimer.stop() }
  Timer { id: holdTimer; interval: 400; onTriggered: root.releaseHold() }

  property real lastGustMs: 0
  property int lastWorkspace: 0
  Connections {
    target: Hyprland
    enabled: store.enabled
    function onRawEvent(event) {
      if (event.name === "workspacev2" || event.name === "activespecial"
          || event.name === "changegroupactive") {
        var fm = Hyprland.focusedMonitor
        root.lastSwitchMs = Date.now()
        root.holdWs = -1
        root.holdGrp = ""
        if (event.name === "workspacev2") {
          var wid = parseInt(String(event.data).split(",")[0])
          if (isFinite(wid)) root.holdWs = wid
        } else if (event.name === "changegroupactive") {
          root.holdGrp = "0x" + event.data
        }
        root.holdTarget = tracker.seqStarted + 1
        root.driftHoldMon = fm ? fm.name : "*"
        holdTimer.restart()
      }
      if (event.name === "closewindow") {
        root.pendingClose["0x" + event.data] = true
      } else if (event.name === "workspacev2" || event.name === "workspace") {
        // With Workspace gust off a workspace switch must not touch the flakes at all.
        var now = Date.now()
        if (!store.workspaceGust || !root.anyLit || now - root.lastGustMs < 150) return
        root.lastGustMs = now
        var id = parseInt(String(event.data).split(",")[0])
        var dir = (isFinite(id) && root.lastWorkspace > 0) ? (id > root.lastWorkspace ? -1 : 1) : -root.gustDir
        if (isFinite(id)) root.lastWorkspace = id
        root.startGust(dir, 0.3, 0.7)
      }
    }
  }

  // ---- actions -------------------------------------------------------------
  function clearSnow() {
    for (var a in root.reg) root.reg[a].a = 0
    root.bank = 0
    publishAccum()
  }

  // Snowglobe shake: every visible window sheds into bursts, a swirling gust, accumulation back to 0.
  function shake() {
    if (!store.enabled) return
    var list = []
    for (var a in root.reg) if (root.reg[a].vis && root.reg[a].a > 0.03) list.push(root.reg[a])
    list.sort(function(p, q) { return q.a * q.w - p.a * p.w })
    var dir = Math.random() < 0.5 ? -1 : 1
    for (var i = 0; i < list.length && i < root.burstSlots; i++)
      root.emitBurst(list[i].mon, list[i].x, list[i].y, list[i].w, list[i].a, store.windX + dir * 0.8)
    clearSnow()
    startGust(dir, 1.0, 0.9)
  }

  // Exponential smoothing step: fraction of the gap closed in dt for time constant tau.
  function ease(dt, tau) { return 1 - Math.exp(-dt / tau) }

  // 0 FPS when disabled or every monitor is guarded by a fullscreen window (the timer simply
  // stops, so dt never accumulates a pause and the phases resume exactly where they were).
  Timer {
    id: clock
    interval: Math.round(1000 / store.fps)
    repeat: true
    running: root.anyLit
    onRunningChanged: if (running) root.lastTick = Date.now()
    onTriggered: {
      var now = Date.now()
      var dt = Math.min(0.25, (now - root.lastTick) / 1000)
      root.lastTick = now

      // Gust impulse eases in (~0.55 s) and out (~1.1 s); effectiveWind eases toward base + gust.
      var gustTarget = root.age < root.gustUntil ? root.gustDir * root.gustAmp : 0
      root.gustImpulse += (gustTarget - root.gustImpulse) * ease(dt, gustTarget !== 0 ? 0.55 : 1.1)
      root.effectiveWind += (store.windX + root.gustImpulse - root.effectiveWind) * ease(dt, 0.3)
      root.windLean += (store.windX - root.windLean) * ease(dt, 0.3)

      // Amount / size ease so sliders and IPC never pop flakes in or out.
      root.amountEased += (store.particleAmount - root.amountEased) * ease(dt, 0.35)
      root.sizeEased += (store.particleSize - root.sizeEased) * ease(dt, 0.35)

      // Particle motion depends on wind and amount only, never on how much snow has settled.
      var fallTarget = 55 * (0.8 + 0.2 * root.amountEased / 1.25) * (1 - 0.15 * Math.min(1, Math.abs(root.gustImpulse)))
      root.effectiveFall += (fallTarget - root.effectiveFall) * ease(dt, 0.4)

      root.windPhase += root.effectiveWind * 220 * dt                // px/s, +E / -W
      root.fallPhase += root.effectiveFall * dt
      root.swayTime = (root.swayTime + dt) % root.swayPeriod
      root.age += dt
      root.updateOffsets()

      // Snow builds in ~30 s at default density and fall; scales with both.
      var rate = Math.max(0.15, (0.5 + store.density) * (0.5 + 0.5 * store.particleAmount / 1.25)) / 30
      if (store.drifts) {
        var changed = false
        for (var addr in root.reg) {
          var o = root.reg[addr]
          // Hidden windows (other workspace / inactive tab) keep their snow but do not grow.
          if (!o.vis || o.a >= 1 || root.settledFs[o.mon]) continue
          o.a = Math.min(1, o.a + rate * dt)
          changed = true
        }
        if (changed) root.publishAccum()
      }
      if (store.bottomBank && root.bank < 1) root.bank = Math.min(1, root.bank + rate * dt / 2.5)
    }
  }

  ShellIpc {
    target: "snowfx"

    function toggle(): void { store.toggle() }
    function setWind(x: real, y: real): void { store.setWind(x, y) }
    function windLeft(): void { store.nudgeWind(-0.15) }
    function windRight(): void { store.nudgeWind(0.15) }
    function nudgeWind(delta: real): void { store.nudgeWind(delta) }
    function resetWind(): void { store.resetWind() }
    function clearSnow(): void { root.clearSnow() }
    function shake(): void { root.shake() }
    function gust(): void { root.startGust(Math.random() < 0.5 ? -1 : 1, 0.7, 0.9) }
    function setAmount(value: real): void { store.setAmount(value) }
    function setSize(value: real): void { store.setSize(value) }
    function setFlow(value: real): void { store.setAmount(value) }   // backwards-compatible alias
    function setDriftStyle(style: string): void { store.setDriftStyle(style) }
    function setSnowman(on: bool): void { store.setSnowman(on) }
    function setSnowmanSwing(on: bool): void { store.setSnowmanSwing(on) }
    function status(): string { return store.snapshot() }
  }

  Component.onCompleted: root.updateOffsets()
  Component.onDestruction: { clock.stop(); guardTimer.stop(); holdTimer.stop() }
}
