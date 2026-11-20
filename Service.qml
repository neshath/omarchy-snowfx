import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// Always-on SnowFx service: per monitor, one click-through Bottom layer (falling
// snow behind windows) and one click-through Overlay layer (snowdrifts, shake-off
// bursts, bottom snowbank and bokeh). One clock drives everything and stops at 0 FPS
// when snow is disabled or every monitor has a fullscreen window.
Item {
  id: root
  property var shell: null

  readonly property alias settings: store
  readonly property alias themePalette: paletteModel
  readonly property alias tracker: tracker

  // Shared animation state (monotonic `age` freezes whenever the clock is stopped).
  property real time: 0                       // wrapped; flake sway only
  property real age: 0
  property vector2d scroll: Qt.vector2d(0, 0) // integrated flake offset in px
  property real lastTick: 0

  // Per-window accumulation 0..1, keyed by Hyprland address.
  property var accum: ({})
  property var reg: ({})                      // addr -> {a, x, y, w, h, mon} (anchor geometry for shake detection)
  property var pendingClose: ({})             // addrs named by a closewindow event
  property real bank: 0                       // bottom snowbank 0..1

  // Shake-off bursts: fixed ring of 6 slots {mon, x, y, w, amount, wind, seed, t0}.
  readonly property int burstSlots: 6
  property var bursts: [null, null, null, null, null, null]
  property int burstHead: 0

  // Gust impulse (workspace switch / shake): decaying envelope over gustSeconds.
  readonly property real gustSeconds: 0.9
  property real gustT0: -100
  property real gustDir: 1
  property real gustAmp: 1.2
  readonly property real gustEnv: {
    var u = (age - gustT0) / gustSeconds
    return (u < 0 || u >= 1) ? 0 : Math.sin(Math.PI * u) * (1 - 0.5 * u)
  }
  readonly property real windEff: store.windX + gustDir * gustAmp * gustEnv

  readonly property color tint: paletteModel.colors[1]
  readonly property color shade: paletteModel.colors[0]
  readonly property real tintMix: 0.16

  // A monitor is lit unless snow is off or a fullscreen window covers it.
  readonly property bool anyLit: {
    if (!store.enabled) return false
    var s = tracker.screens
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var info = s[Quickshell.screens[i].name]
      if (!info || !info.fullscreen) return true
    }
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

  function startGust(dir, amp) {
    root.gustDir = dir
    root.gustAmp = amp
    root.gustT0 = root.age
  }

  // ---- window accumulation / shed / close detection ------------------------
  function syncWindows() {
    var cur = {}
    var s = tracker.screens
    for (var name in s) {
      var ws = s[name].windows
      for (var i = 0; i < ws.length; i++)
        if (ws[i].addr) cur[ws[i].addr] = { x: ws[i].x, y: ws[i].y, w: ws[i].w, h: ws[i].h, mon: name }
    }
    var next = {}
    for (var addr in root.reg) {
      if (cur[addr]) continue
      var gone = root.reg[addr]
      // Closed (not merely hidden by a workspace switch): the snow falls off.
      if (root.pendingClose[addr] && gone.a > 0.05) root.emitBurst(gone.mon, gone.x, gone.y, gone.w, gone.a, root.windEff)
      delete root.pendingClose[addr]
    }
    for (var a in cur) {
      var c = cur[a], o = root.reg[a]
      if (!o) { next[a] = { a: 0, x: c.x, y: c.y, w: c.w, h: c.h, mon: c.mon }; continue }
      var jump = Math.abs(c.x - o.x) > 24 || Math.abs(c.y - o.y) > 24 || Math.abs(c.w - o.w) > 24 || c.mon !== o.mon
      if (jump) {
        var amt = o.a * (0.35 + 0.2 * Math.random())    // drag-to-shake: shed 35-55%
        if (o.a > 0.05) root.emitBurst(o.mon, o.x, o.y, o.w, amt * 0.7, root.windEff)
        o.a -= amt
        o.x = c.x; o.y = c.y; o.w = c.w; o.mon = c.mon
      }
      o.h = c.h
      next[a] = o
    }
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
    function onScreensChanged() { root.syncWindows() }
  }

  property real lastGustMs: 0
  property int lastWorkspace: 0
  Connections {
    target: Hyprland
    enabled: store.enabled
    function onRawEvent(event) {
      if (event.name === "closewindow") {
        root.pendingClose["0x" + event.data] = true
      } else if (event.name === "workspacev2" || event.name === "workspace") {
        var now = Date.now()
        if (!store.workspaceGust || !root.anyLit || now - root.lastGustMs < 150) return
        root.lastGustMs = now
        var id = parseInt(String(event.data).split(",")[0])
        var dir = (isFinite(id) && root.lastWorkspace > 0) ? (id > root.lastWorkspace ? -1 : 1) : -root.gustDir
        if (isFinite(id)) root.lastWorkspace = id
        root.startGust(dir, 1.2)
      }
    }
  }

  // ---- actions -------------------------------------------------------------
  function clearSnow() {
    for (var a in root.reg) root.reg[a].a = 0
    root.bank = 0
    publishAccum()
  }

  // Snowglobe shake: every window sheds into bursts, a swirling gust, accumulation back to 0.
  function shake() {
    if (!store.enabled) return
    var list = []
    for (var a in root.reg) if (root.reg[a].a > 0.03) list.push(root.reg[a])
    list.sort(function(p, q) { return q.a * q.w - p.a * p.w })
    var dir = Math.random() < 0.5 ? -1 : 1
    for (var i = 0; i < list.length && i < root.burstSlots; i++)
      root.emitBurst(list[i].mon, list[i].x, list[i].y, list[i].w, list[i].a, store.windX + dir * 0.8)
    clearSnow()
    startGust(dir, 1.6)
  }

  // 0 FPS when disabled or every monitor is guarded by a fullscreen window.
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
      var env = root.gustEnv
      // Particle motion depends on wind and amount only, never on how much snow has settled.
      var fallSpeed = 55 * (0.8 + 0.2 * store.particleAmount / 1.25) * (1 - 0.5 * env)
      var windSpeed = 220 * root.windEff                                  // px/s, +E / -W
      var swirl = 70 * env * Math.sin(root.time * 9)
      root.scroll = Qt.vector2d((root.scroll.x + windSpeed * dt) % 100000,
                                (root.scroll.y + (fallSpeed + swirl) * dt) % 100000)
      root.time = (root.time + dt) % 3600
      root.age += dt

      // Snow builds in ~30 s at default density and fall; scales with both.
      var rate = Math.max(0.15, (0.5 + store.density) * (0.5 + 0.5 * store.particleAmount / 1.25)) / 30
      if (store.drifts) {
        var changed = false
        var s = tracker.screens
        for (var addr in root.reg) {
          var o = root.reg[addr]
          var info = s[o.mon]
          if (o.a >= 1 || (info && info.fullscreen)) continue
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
    function gust(): void { root.startGust(Math.random() < 0.5 ? -1 : 1, 1.4) }
    function setAmount(value: real): void { store.setAmount(value) }
    function setSize(value: real): void { store.setSize(value) }
    function setFlow(value: real): void { store.setAmount(value) }   // backwards-compatible alias
    function setDriftStyle(style: string): void { store.setDriftStyle(style) }
    function status(): string { return store.snapshot() }
  }

  Component.onDestruction: clock.stop()
}
