import QtQuick
import Quickshell
import Quickshell.Io

// Settings persisted in ~/.config/omarchy/snowfx.json. The service and the
// popover each hold a store; the file watcher keeps them in sync.
Item {
  id: root
  visible: false

  property bool enabled: true
  property bool drifts: true          // snowdrifts on window top edges
  property real density: 0.6          // 0.1 .. 1
  property real windX: 0.0            // -1 (W) .. 1 (E): wind strength + direction
  property real particleAmount: 1.25  // 0.1 .. 2.5: how many particles spawn (independent of buildup)
  property real particleSize: 1.0     // 0.5 .. 2.2: particle radius multiplier
  property string driftStyle: "flat"  // "flat" | "sculpted"
  property bool workspaceGust: true   // wind gust on workspace switch
  property bool bottomBank: true      // thin snowbank along each monitor's bottom edge
  property int fps: 30                // 30 | 60

  property var recentWrites: []       // our own recent snapshots; late watcher events must not revert newer state

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, Number(v))) }

  function applyJson(text) {
    if (recentWrites.indexOf(text) >= 0 || saveTimer.running) return
    var j
    try { j = JSON.parse(text) } catch (e) { return }
    if (typeof j !== "object" || j === null) return
    if (typeof j.enabled === "boolean") enabled = j.enabled
    if (typeof j.drifts === "boolean") drifts = j.drifts
    if (isFinite(j.density)) density = clamp(j.density, 0.1, 1)
    if (isFinite(j.windX)) windX = clamp(j.windX, -1, 1)
    if (isFinite(j.particleAmount)) particleAmount = clamp(j.particleAmount, 0.1, 2.5)
    if (isFinite(j.particleSize)) particleSize = clamp(j.particleSize, 0.5, 2.2)
    if (j.driftStyle === "flat" || j.driftStyle === "sculpted") driftStyle = j.driftStyle
    if (typeof j.workspaceGust === "boolean") workspaceGust = j.workspaceGust
    if (typeof j.bottomBank === "boolean") bottomBank = j.bottomBank
    if (isFinite(j.fps)) fps = Number(j.fps) <= 30 ? 30 : 60
  }

  function snapshot() {
    function r(v) { return Math.round(v * 100) / 100 }
    return JSON.stringify({ enabled: enabled, drifts: drifts, density: r(density),
      windX: r(windX), particleAmount: r(particleAmount), particleSize: r(particleSize), driftStyle: driftStyle,
      workspaceGust: workspaceGust, bottomBank: bottomBank, fps: fps }, null, 2) + "\n"
  }

  function save() { saveTimer.restart() }

  function toggle() { enabled = !enabled; save() }
  function setDrifts(v) { drifts = !!v; save() }
  function setDriftStyle(v) {
    if (v !== "flat" && v !== "sculpted") return false
    driftStyle = v; save(); return true
  }
  function setWorkspaceGust(v) { workspaceGust = !!v; save() }
  function setBottomBank(v) { bottomBank = !!v; save() }
  function setDensity(v) { density = clamp(v, 0.1, 1); save() }
  // y is the particle amount (0.1 .. 2.5), the pad's vertical axis.
  function setWind(x, y) {
    if (!isFinite(x)) return false
    windX = clamp(x, -1, 1)
    if (isFinite(y)) particleAmount = clamp(y, 0.1, 2.5)
    save(); return true
  }
  function setAmount(v) { if (!isFinite(v)) return false; particleAmount = clamp(v, 0.1, 2.5); save(); return true }
  function setSize(v) { if (!isFinite(v)) return false; particleSize = clamp(v, 0.5, 2.2); save(); return true }
  function setFps(v) { fps = Number(v) <= 30 ? 30 : 60; save() }
  function nudgeWind(d) {
    if (!isFinite(d)) return false
    windX = Math.round(clamp(windX + Number(d), -1, 1) * 100) / 100
    save(); return true
  }
  function nudgeAmount(d) {
    if (!isFinite(d)) return false
    particleAmount = Math.round(clamp(particleAmount + Number(d), 0.1, 2.5) * 100) / 100
    save(); return true
  }
  function resetWind() { windX = 0; particleAmount = 1.25; save() }

  // "83% · W", "68% · E", "0% · Calm"
  readonly property int windPercent: Math.round(Math.abs(windX) * 100)
  readonly property string windLabel: windPercent === 0 ? "0% · Calm" : windPercent + "% · " + (windX < 0 ? "W" : "E")

  Timer {
    id: saveTimer
    interval: 150
    onTriggered: {
      var snap = root.snapshot()
      root.recentWrites = root.recentWrites.concat([snap]).slice(-8)
      file.setText(snap)
    }
  }

  FileView {
    id: file
    path: Quickshell.env("HOME") + "/.config/omarchy/snowfx.json"
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onFileChanged: reload()
    onLoaded: root.applyJson(text())
    onLoadFailed: function(error) { if (error === FileViewError.FileNotFound) root.save() }
  }

  Component.onDestruction: saveTimer.stop()
}
