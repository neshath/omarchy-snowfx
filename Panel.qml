import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.neshath.snowfx"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property bool moreOpen: false

  function open() { root.controller.show() }
  function openFromHotkey() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  // The service owns shake; reach it in-process through the shell's IPC registry.
  function shake() { IpcRegistry.call("snowfx", "shake", []) }

  SettingsStore { id: store }

  readonly property color fg: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color popBg: Commons.Color.popups.background
  readonly property color mutedFg: Qt.alpha(fg, 0.45)
  readonly property bool rounded: Style.cornerRadius > 0
  function pill(h) { return rounded ? h / 2 : 0 }
  function soft(r) { return rounded ? r : 0 }

  readonly property real amountFrac: (store.particleAmount - 0.1) / 2.4
  readonly property real calmFrac: (1.25 - 0.1) / 2.4

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: Item {
      id: body
      implicitHeight: (root.moreOpen ? moreCol.y + moreCol.height : moreRow.y + moreRow.height) + Style.space(12)

      // KeyboardPanel focuses this item on open (OnDemand layer focus, released on close).
      // Left/Right: wind. Up/Down: particle amount. Shift = fine steps; auto-repeat works.
      focus: true
      Keys.onPressed: function(event) {
        var fine = (event.modifiers & Qt.ShiftModifier) !== 0
        switch (event.key) {
        case Qt.Key_Left:  store.nudgeWind(fine ? -0.02 : -0.10); break
        case Qt.Key_Right: store.nudgeWind(fine ? 0.02 : 0.10); break
        case Qt.Key_Up:    store.nudgeAmount(fine ? 0.02 : 0.10); break
        case Qt.Key_Down:  store.nudgeAmount(fine ? -0.02 : -0.10); break
        case Qt.Key_0:
        case Qt.Key_R:     store.resetWind(); break
        case Qt.Key_S:     root.shake(); break
        case Qt.Key_Escape: root.close(); break
        default: return
        }
        event.accepted = true
      }

      // ---- Header: title + On/Off ---------------------------------------
      Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Style.space(30)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Wind"
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        PowerSwitch { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          on: store.enabled; onToggled: store.toggle() }
      }

      // ---- Wind pad: X = wind, Y = particle amount --------------------------
      Rectangle {
        id: pad
        anchors { top: header.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right }
        height: Style.space(140)
        radius: root.soft(Style.space(14))
        color: Qt.alpha(root.fg, 0.06)
        border.width: 1
        border.color: Qt.alpha(root.fg, 0.12)
        clip: true
        opacity: store.enabled ? 1 : 0.5

        readonly property real cx: width / 2
        readonly property real cy: (1 - root.calmFrac) * height        // default amount = center line
        readonly property real kx: (store.windX + 1) / 2 * width
        readonly property real ky: (1 - root.amountFrac) * height
        readonly property real vx: kx - cx
        readonly property real vy: ky - cy

        Rectangle { x: pad.cx; width: 1; height: parent.height; color: Qt.alpha(root.fg, 0.10) }
        Rectangle { y: pad.cy; height: 1; width: parent.width; color: Qt.alpha(root.fg, 0.10) }

        Text { text: "W"; color: root.mutedFg; font.family: Style.font.family; font.pixelSize: Style.font.caption
          anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter }
        Text { text: "E"; color: root.mutedFg; font.family: Style.font.family; font.pixelSize: Style.font.caption
          anchors.right: parent.right; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter }
        Text { text: "More snow"; color: root.mutedFg; font.family: Style.font.family; font.pixelSize: Style.font.caption
          anchors.top: parent.top; anchors.topMargin: Style.space(5); anchors.horizontalCenter: parent.horizontalCenter }
        Text { text: "Less"; color: root.mutedFg; font.family: Style.font.family; font.pixelSize: Style.font.caption
          anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(5); anchors.horizontalCenter: parent.horizontalCenter }

        Rectangle {   // vector arrow from the calm point to the knob
          x: pad.cx; y: pad.cy - height / 2
          width: Math.sqrt(pad.vx * pad.vx + pad.vy * pad.vy)
          height: 2
          transformOrigin: Item.Left
          rotation: Math.atan2(pad.vy, pad.vx) * 180 / Math.PI
          color: root.accent
          visible: width > 1
        }
        Rectangle {
          x: pad.cx - width / 2; y: pad.cy - height / 2
          width: Style.space(6); height: width; radius: width / 2
          color: Qt.alpha(root.fg, 0.5)
        }
        Rectangle {   // knob = arrow head
          x: pad.kx - width / 2; y: pad.ky - height / 2
          width: padMa.pressed ? Style.space(20) : Style.space(16); height: width; radius: width / 2
          color: root.fg
          border.width: 3
          border.color: root.accent
          Behavior on width { NumberAnimation { duration: 90 } }
        }

        MouseArea {
          id: padMa
          anchors.fill: parent
          preventStealing: true
          cursorShape: Qt.CrossCursor
          function setFrom(mx, my) {
            var x = Math.max(-1, Math.min(1, mx / pad.width * 2 - 1))
            var f = 0.1 + 2.4 * Math.max(0, Math.min(1, 1 - my / pad.height))
            if (Math.abs(x) < 0.04) x = 0          // snap to calm
            if (Math.abs(f - 1.25) < 0.06) f = 1.25
            store.setWind(x, f)
          }
          onPressed: function(m) { setFrom(m.x, m.y) }
          onPositionChanged: function(m) { if (pressed) setFrom(m.x, m.y) }
        }
      }

      // ---- Readout + hint -------------------------------------------------
      Column {
        id: readout
        anchors { top: pad.bottom; topMargin: Style.space(8); left: parent.left; right: parent.right }
        spacing: Style.space(2)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: store.windLabel
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Drag or ← / → keys  ·  ↑ / ↓ amount  ·  Shift fine"
          color: Qt.alpha(root.fg, 0.32)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption - 1
        }
      }

      // ---- Amount + Size sliders ----------------------------------------------
      Slim {
        id: amountRow
        anchors { top: readout.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right }
        label: "Amount"
        display: Math.round(store.particleAmount * 100) + "%"
        from: 0.1; to: 2.5
        value: store.particleAmount
        onMoved: function(v) { store.setAmount(v) }
      }
      Slim {
        id: sizeRow
        anchors { top: amountRow.bottom; topMargin: Style.space(4); left: parent.left; right: parent.right }
        label: "Size"
        display: Math.round(store.particleSize * 100) + "%"
        from: 0.5; to: 2.2
        value: store.particleSize
        onMoved: function(v) { store.setSize(v) }
      }

      // ---- Drift style pill + Shake ---------------------------------------
      Item {
        id: styleRow
        anchors { top: sizeRow.bottom; topMargin: Style.space(8); left: parent.left; right: parent.right }
        height: Style.space(28)

        Segmented {
          anchors { left: parent.left; right: shakeBtn.left; rightMargin: Style.space(8) }
          labels: ["Flat", "Sculpted"]
          current: store.driftStyle === "sculpted" ? 1 : 0
          onPicked: function(i) { store.setDriftStyle(i === 1 ? "sculpted" : "flat") }
        }
        Rectangle {
          id: shakeBtn
          anchors.right: parent.right
          width: Style.space(76); height: parent.height
          radius: root.pill(height)
          color: shakeMa.containsMouse ? Qt.alpha(root.accent, 0.35) : Qt.alpha(root.accent, 0.18)
          border.width: 1
          border.color: Qt.alpha(root.accent, 0.6)
          Text {
            anchors.centerIn: parent
            text: "Shake"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: shakeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.shake()
          }
        }
      }

      // ---- More drawer -------------------------------------------------------
      Item {
        id: moreRow
        anchors { top: styleRow.bottom; topMargin: Style.space(10); left: parent.left; right: parent.right }
        height: Style.space(22)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: (root.moreOpen ? "▾ " : "▸ ") + "More"
          color: moreMa.containsMouse ? root.fg : root.mutedFg
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        MouseArea {
          id: moreMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.moreOpen = !root.moreOpen
        }
      }
      Column {
        id: moreCol
        visible: root.moreOpen
        anchors { top: moreRow.bottom; topMargin: Style.space(6); left: parent.left; right: parent.right }
        spacing: Style.space(6)

        ToggleRow { label: "Window snow"; on: store.drifts; onToggled: store.setDrifts(!store.drifts) }
        ToggleRow { label: "Bottom bank"; on: store.bottomBank; onToggled: store.setBottomBank(!store.bottomBank) }
        ToggleRow { label: "Workspace gust"; on: store.workspaceGust; onToggled: store.setWorkspaceGust(!store.workspaceGust) }
        Slim {
          width: parent.width
          label: "Buildup"
          display: Math.round(store.density * 100) + "%"
          from: 0.1; to: 1.0
          value: store.density
          onMoved: function(v) { store.setDensity(v) }
        }
        Item {
          width: parent.width; height: Style.space(28)
          Text {
            id: fpsLabel
            anchors.verticalCenter: parent.verticalCenter
            text: "FPS"
            color: root.mutedFg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Segmented {
            anchors { left: fpsLabel.right; leftMargin: Style.space(8); right: resetBtn.left; rightMargin: Style.space(8) }
            labels: ["30", "60"]
            current: store.fps >= 60 ? 1 : 0
            onPicked: function(i) { store.setFps(i === 1 ? 60 : 30) }
          }
          Rectangle {
            id: resetBtn
            anchors.right: parent.right
            width: Style.space(64); height: parent.height
            radius: root.pill(height)
            color: resetMa.containsMouse ? Qt.alpha(root.fg, 0.14) : Qt.alpha(root.fg, 0.07)
            border.width: 1
            border.color: Qt.alpha(root.fg, 0.12)
            Text {
              anchors.centerIn: parent
              text: "Reset"
              color: resetMa.containsMouse ? root.fg : root.mutedFg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: resetMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: store.resetWind()
            }
          }
        }
      }
    }
  }

  component PowerSwitch: Rectangle {
    id: sw
    property bool on: false
    signal toggled()
    width: Style.space(40); height: Style.space(22)
    radius: root.pill(height)
    color: on ? Qt.alpha(root.accent, 0.9) : Qt.alpha(root.fg, 0.16)
    Behavior on color { ColorAnimation { duration: 160 } }
    Rectangle {
      width: parent.height - Style.space(6); height: width
      radius: root.pill(height)
      anchors.verticalCenter: parent.verticalCenter
      x: sw.on ? parent.width - width - Style.space(3) : Style.space(3)
      color: sw.on ? root.popBg : root.fg
      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
  }

  component ToggleRow: Item {
    id: tr
    property string label: ""
    property bool on: false
    signal toggled()
    width: parent ? parent.width : 0
    height: Style.space(26)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tr.label
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    PowerSwitch { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; on: tr.on; onToggled: tr.toggled() }
  }

  component Segmented: Item {
    id: seg
    property var labels: []
    property int current: 0
    signal picked(int i)
    height: Style.space(28)
    readonly property real cell: (width - Style.space(4)) / Math.max(1, labels.length)

    Rectangle {
      anchors.fill: parent
      radius: root.pill(height)
      color: Qt.alpha(root.fg, 0.07)
      border.width: 1
      border.color: Qt.alpha(root.fg, 0.12)
    }
    Rectangle {
      x: Style.space(2) + seg.current * seg.cell
      y: Style.space(2)
      width: seg.cell
      height: parent.height - Style.space(4)
      radius: root.pill(height)
      color: Qt.alpha(root.accent, 0.28)
      border.width: 1
      border.color: Qt.alpha(root.accent, 0.9)
      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    Row {
      x: Style.space(2); y: Style.space(2)
      Repeater {
        model: seg.labels
        Item {
          required property int index
          required property var modelData
          width: seg.cell
          height: seg.height - Style.space(4)
          Text {
            anchors.centerIn: parent
            text: parent.modelData
            color: seg.current === parent.index ? root.fg : root.mutedFg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: seg.current === parent.index
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(parent.index) }
        }
      }
    }
  }

  // Slim slider: filled track, round handle, right-aligned live value pill.
  component Slim: Item {
    id: sl
    property string label: ""
    property string display: ""
    property real from: 0
    property real to: 1
    property real value: 0
    signal moved(real v)
    height: Style.space(42)
    readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))

    Text {
      text: sl.label
      color: root.mutedFg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      anchors.right: parent.right
      height: Style.space(18)
      width: valueText.implicitWidth + Style.space(14)
      radius: root.pill(height)
      color: Qt.alpha(root.fg, 0.08)
      Text {
        id: valueText
        anchors.centerIn: parent
        text: sl.display
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    Rectangle {
      id: track
      anchors.left: parent.left; anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(6)
      height: Style.space(4)
      radius: root.pill(height)
      color: Qt.alpha(root.fg, 0.16)
      Rectangle { width: track.width * sl.frac; height: parent.height; radius: parent.radius; color: root.accent }
      Rectangle {
        x: track.width * sl.frac - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: handleMa.pressed ? Style.space(15) : Style.space(13)
        height: width
        radius: width / 2
        color: root.fg
        border.width: 2
        border.color: root.accent
        Behavior on width { NumberAnimation { duration: 90 } }
      }
      MouseArea {
        id: handleMa
        anchors.fill: parent
        anchors.topMargin: -Style.space(10); anchors.bottomMargin: -Style.space(10)
        preventStealing: true
        function setFrom(mx) { sl.moved(sl.from + (sl.to - sl.from) * Math.max(0, Math.min(1, mx / track.width))) }
        onPressed: function(m) { setFrom(m.x) }
        onPositionChanged: function(m) { if (pressed) setFrom(m.x) }
      }
    }
  }
}
