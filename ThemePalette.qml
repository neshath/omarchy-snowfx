import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Four theme tokens from the active Omarchy colors.toml (absolute $HOME path,
// per-token fallback to Commons.Color). Snow is mostly white; the palette only
// tints it and its drift shadows so every theme feels different.
Item {
  id: root
  visible: false

  readonly property var tokens: ["accent", "cyan", "foreground", "background"]
  property var colors: fallbackColors()

  function fallbackFor(i) {
    var c = Commons.Color
    return String([c.accent, c.accent, c.foreground, c.background][i])
  }
  function fallbackColors() {
    var out = []
    for (var i = 0; i < tokens.length; i++) out.push(fallbackFor(i))
    return out
  }

  function apply(text) {
    var map = {}
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = /^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9a-fA-F]{6,8})["']?/.exec(lines[i])
      if (m) map[m[1]] = m[2]
    }
    var out = []
    for (var j = 0; j < tokens.length; j++) out.push(map[tokens[j]] || fallbackFor(j))
    root.colors = out
  }

  FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.colors = root.fallbackColors()
  }

  // Theme swaps replace the theme directory; poke a reload when shell colors change.
  Connections {
    target: Commons.Color
    function onAccentChanged() { colorsFile.reload() }
    function onBackgroundChanged() { colorsFile.reload() }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); colorsFile.reload() }
    onLoaded: colorsFile.reload()
  }
}
