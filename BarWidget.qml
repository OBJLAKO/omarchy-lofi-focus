import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget for sky.lofi.
//   Left click   - play the saved station (stop -> play, playing -> pause,
//                  paused -> resume)
//   Right click  - open the listening / settings panel
//   Middle click - next station in the current category
//   Wheel        - adjust master volume for all channels
BarWidget {
  id: root
  moduleName: "sky.lofi"

  // ---- Player state, mirrored from $XDG_RUNTIME_DIR/sky.lofi/status.json
  property bool playerRunning: false
  property bool playerPaused: false
  property string stationName: ""
  property string categoryName: ""
  property string bgName: ""
  property bool mixOn: false
  property int masterVolume: 100
  property int bgVolume: 40
  property bool statusReady: false
  property string statusJson: ""
  property int pendingMasterVolume: -1
  property var actionQueue: []

  readonly property string playerPath: Qt.resolvedUrl("lofi-player").toString().replace(/^file:\/\//, "")
  readonly property string statusPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sky.lofi/status.json"

  // ---- Panel plumbing. Shape contract the bar host expects on the widget
  //      root: open/close/opened/togglePanel/closeForPopoutSwitch.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if (root.statusJson) target.applyStatus(root.statusJson)
  }

  function singleLineText(value, limit) {
    return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, limit)
  }

  function applyStatus(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var state = JSON.parse(raw)
      if (typeof state.running !== "boolean" || typeof state.paused !== "boolean") return
      root.statusJson = raw
      root.playerRunning = state.running === true
      root.playerPaused = state.paused === true
      root.stationName = root.singleLineText(state.name || "", 120)
      root.categoryName = root.singleLineText(state.category_name || "", 60)
      root.bgName = root.singleLineText(state.bg_name || "", 120)
      root.mixOn = state.mix === true
      if (!volumeProcess.running && root.pendingMasterVolume < 0) root.masterVolume = Math.max(0, Math.min(100, Math.round(Number(state.master_volume === undefined ? 100 : state.master_volume)) || 0))
      root.bgVolume = Math.max(0, Math.min(100, Math.round(Number(state.bg_volume === undefined ? 40 : state.bg_volume)) || 0))
    } catch (error) {
      console.warn("Lofi status parse:", String(error))
      return
    }
  }

  function refreshStatus() {
    if (!statusInitProcess.running) statusInitProcess.running = true
  }

  function runAction(args) {
    if (actionProcess.running) { root.actionQueue.push(args); return }
    actionProcess.command = [root.playerPath].concat(args)
    actionProcess.running = true
  }

  function setMasterVolume(value) {
    root.masterVolume = Math.max(0, Math.min(100, Math.round(value)))
    root.pendingMasterVolume = root.masterVolume
    root.flushVolume()
  }

  function changeMasterVolume(delta) {
    if (delta === 0) return
    root.setMasterVolume(root.masterVolume + (delta > 0 ? 5 : -5))
  }

  function flushVolume() {
    if (volumeProcess.running || root.pendingMasterVolume < 0) return
    volumeProcess.command = [root.playerPath, "vol", "master", String(root.pendingMasterVolume)]
    root.pendingMasterVolume = -1
    volumeProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- Status polling
  FileView {
    id: statusFile
    path: root.statusReady ? root.statusPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyStatus(text())
    onFileChanged: reload()
  }

  Process {
    id: statusInitProcess
    command: [root.playerPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusReady = true
    }
  }

  Process {
    id: actionProcess
    command: []
    onExited: function(exitCode) {
      if (root.actionQueue.length) { var next = root.actionQueue.shift(); Qt.callLater(function() { root.runAction(next) }) }
      if (exitCode === 0) root.statusReady = true
      Qt.callLater(root.refreshStatus)
    }
  }

  Process {
    id: volumeProcess
    command: []
    onExited: function(exitCode) {
      Qt.callLater(root.flushVolume)
      Qt.callLater(root.refreshStatus)
    }
  }

  Component.onCompleted: {
    statusInitProcess.command = [root.playerPath, "status"]
    statusInitProcess.running = true
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      if (!statusInitProcess.running && !actionProcess.running && !volumeProcess.running)
        statusInitProcess.running = true
    }
  }

  // ---- Panel instance (hidden; owns the popup content)
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "sky.lofi"

    function status(): string { return root.statusJson }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function play(): void { root.runAction(["play"]) }
    function pause(): void { root.runAction(["pause"]) }
    function resume(): void { root.runAction(["resume"]) }
    function stop(): void { root.runAction(["stop"]) }
    function next(): void { root.runAction(["next"]) }
    function prev(): void { root.runAction(["prev"]) }
    function mix(): void { root.runAction(["mix", "toggle"]) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    labelVisible: false
    fixedWidth: root.vertical ? root.barSize : Style.space(30)
    Canvas {
      anchors.centerIn: parent
      width: Style.space(18)
      height: Style.space(18)
      property color ink: button.active ? button.activeColor : button.foreground
      onInkChanged: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.reset(); c.scale(width / 24, height / 24)
        c.strokeStyle = ink; c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round"
        c.beginPath(); c.moveTo(4,8); c.lineTo(16,8); c.lineTo(16,14)
        c.quadraticCurveTo(16,18,12,18); c.lineTo(8,18); c.quadraticCurveTo(4,18,4,14); c.closePath(); c.stroke()
        c.beginPath(); c.moveTo(16,9); c.lineTo(18,9); c.bezierCurveTo(23,9,23,15,16,15); c.stroke()
        c.beginPath(); c.moveTo(3,21); c.lineTo(21,21); c.moveTo(8,5); c.lineTo(8,3); c.moveTo(13,5); c.lineTo(13,3); c.stroke()
      }
    }
    active: root.playerRunning && !root.playerPaused
    dimmed: root.playerRunning && root.playerPaused
    tooltipText: root.playerRunning
      ? (root.playerPaused ? "Paused: " : "Playing: ")
        + root.singleLineText(root.stationName, 80)
        + (root.mixOn && root.bgName ? "  +  " + root.singleLineText(root.bgName, 80) : "")
      : "Lofi Radio — left click to play, right click for stations"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.togglePanel()
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        root.runAction(["next"])
        return
      }
      // Left click: play / pause / resume.
      root.runAction(["toggle"])
    }

    onWheelMoved: function(delta) {
      root.changeMasterVolume(delta)
    }
  }
}
