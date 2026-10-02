import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// QML owns presentation; one persistent Rust client owns transport. Audio keeps
// running when a panel closes or the shell disconnects from this client.
BarWidget {
  id: root
  moduleName: "sky.lofi"
  property bool playerRunning: false
  property bool playerPaused: false
  property bool musicRunning: false
  property string mainState: "stopped"
  property int mainVolume: 80
  property bool backgroundRunning: false
  property string backgroundState: "stopped"
  property var natureLayers: []
  property bool animationsEnabled: true
  property bool equalizerEnabled: true
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
  property var pendingRequests: ({})
  readonly property int pendingRequestCount: Object.keys(root.pendingRequests).length
  property int nextRequestId: 0
  property string actionError: ""
  property int reconnectDelay: 300
  signal actionFinished(var arguments, int exitCode, string message)
  readonly property string playerPath: Qt.resolvedUrl("lofi-player").toString().replace(/^file:\/\//, "")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool playbackChannels: (root.musicRunning && root.mainState === "playing")
    || (root.backgroundRunning && root.backgroundState === "playing")
    || root.natureLayers.some(function(layer) { return layer.running === true })
  readonly property bool audibleChannels: (root.musicRunning && root.mainState === "playing" && root.mainVolume > 0)
    || (root.backgroundRunning && root.backgroundState === "playing" && root.bgVolume > 0)
    || root.natureLayers.some(function(layer) { return layer.running === true && Number(layer.volume) > 0 })
  readonly property bool playbackActive: root.statusReady && root.playerRunning && !root.playerPaused && root.masterVolume > 0 && root.audibleChannels
  readonly property string playbackLabel: root.playerPaused ? "Paused"
    : root.playbackActive ? "Playing"
    : root.playbackChannels && (root.masterVolume === 0 || !root.audibleChannels) ? "Muted"
    : root.mainState === "ended" ? "Finished"
    : root.mainState === "failed" ? "Source unavailable"
    : root.mainState === "reconnecting" ? "Reconnecting"
    : "Connecting"
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    if (root.statusJson) target.applyStatus(root.statusJson)
  }
  function singleLineText(value, limit) { return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, limit) }
  function applyStatus(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var state = JSON.parse(raw)
      if (typeof state.running !== "boolean" || typeof state.paused !== "boolean") return
      root.statusJson = raw
      root.playerRunning = state.running === true
      root.playerPaused = state.paused === true
      root.musicRunning = state.main_running === true
      root.mainState = String(state.main_state || (root.musicRunning ? "playing" : "stopped"))
      root.mainVolume = Math.max(0, Math.min(100, Math.round(Number(state.main_volume === undefined ? 80 : state.main_volume)) || 0))
      root.backgroundRunning = state.bg_running === true
      root.backgroundState = String(state.bg_state || (root.backgroundRunning ? "playing" : "stopped"))
      root.natureLayers = Array.isArray(state.nature_layers) ? state.nature_layers : []
      root.animationsEnabled = state.animations !== false
      root.equalizerEnabled = state.equalizer_animation !== false
      root.stationName = root.singleLineText(state.name, 120)
      root.categoryName = root.singleLineText(state.category_name, 60)
      root.bgName = root.singleLineText(state.bg_name, 120)
      root.mixOn = state.mix === true
      if (root.pendingMasterVolume < 0) root.masterVolume = Math.max(0, Math.min(100, Math.round(Number(state.master_volume === undefined ? 100 : state.master_volume)) || 0))
      root.bgVolume = Math.max(0, Math.min(100, Math.round(Number(state.bg_volume === undefined ? 40 : state.bg_volume)) || 0))
    } catch (error) { console.warn("Skylofi status:", String(error)) }
  }
  function acceptReply(line) {
    try {
      if (!line || line.length > 65536) return
      var reply = JSON.parse(line)
      if (reply.status) {
        root.applyStatus(JSON.stringify(reply.status))
        root.statusReady = true
        root.reconnectDelay = 300
      }
      if (reply.id !== undefined) {
        var args = root.pendingRequests[reply.id]
        if (args) {
          var pending = Object.assign({}, root.pendingRequests)
          delete pending[reply.id]
          root.pendingRequests = pending
          root.actionError = reply.ok === false ? root.singleLineText(reply.error || "Could not complete that action.", 300) : ""
          root.actionFinished(args.arguments, reply.ok === false ? 1 : 0, root.actionError)
        }
      }
      if (root.statusReady && root.actionQueue.length) {
        var queued = root.actionQueue
        root.actionQueue = []
        for (var i = 0; i < queued.length; ++i) root.runAction(queued[i])
      }
    } catch (error) { console.warn("Skylofi transport:", String(error)) }
  }
  function refreshStatus() { root.runAction(["status"]) }
  function runAction(args) {
    if (!root.statusReady || !backend.running) {
      if (args[0] === "vol") {
        for (var i = root.actionQueue.length - 1; i >= 0; --i) {
          if (root.actionQueue[i][0] === "vol" && root.actionQueue[i][1] === args[1]) {
            root.actionQueue[i] = args
            return
          }
        }
      }
      if (root.actionQueue.length < 32) root.actionQueue = root.actionQueue.concat([args])
      else root.actionFinished(args, 1, "Player is reconnecting. Try again shortly.")
      if (!backend.running) backend.running = true
      return
    }
    if (root.pendingRequestCount >= 64) {
      root.actionFinished(args, 1, "Player is busy. This action was not sent.")
      return
    }
    var requestId = ++root.nextRequestId
    var pending = Object.assign({}, root.pendingRequests)
    pending[requestId] = { arguments: args, deadline: Date.now() + 15000 }
    root.pendingRequests = pending
    backend.write(JSON.stringify({ id: requestId, args: args }) + "\n")
  }
  function setMasterVolume(value) {
    root.masterVolume = Math.max(0, Math.min(100, Math.round(value)))
    root.pendingMasterVolume = root.masterVolume
    volumeDebounce.restart()
  }
  function changeMasterVolume(delta) { if (delta) root.setMasterVolume(root.masterVolume + (delta > 0 ? 5 : -5)) }
  function flushVolume() {
    if (root.pendingMasterVolume < 0) return
    var volume = root.pendingMasterVolume
    root.pendingMasterVolume = -1
    root.runAction(["vol", "master", String(volume)])
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: backend
    command: [root.playerPath, "--stdio"]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.acceptReply(line) } }
    onRunningChanged: if (!running && !reconnect.running) reconnect.restart()
    onExited: function(exitCode) {
      root.statusReady = false
      var requests = root.pendingRequests
      root.pendingRequests = ({})
      for (var key in requests) root.actionFinished(requests[key].arguments, 1, "Connection interrupted. This action may have completed; check playback before trying again.")
      root.reconnectDelay = Math.min(30000, root.reconnectDelay * 2)
      reconnect.restart()
    }
  }
  Timer {
    id: reconnect
    interval: root.reconnectDelay
    repeat: false
    onTriggered: if (!backend.running) backend.running = true
  }
  Timer { id: volumeDebounce; interval: 45; onTriggered: root.flushVolume() }
  Timer {
    interval: 15000
    running: backend.running && !root.statusReady
    onTriggered: backend.running = false
  }
  Timer {
    interval: 15000
    running: root.actionQueue.length > 0
    onTriggered: {
      var queued = root.actionQueue
      root.actionQueue = []
      for (var i = 0; i < queued.length; ++i) root.actionFinished(queued[i], 1, "Player unavailable. This action was not sent.")
    }
  }
  Timer {
    interval: 1000
    repeat: true
    running: root.pendingRequestCount > 0
    onTriggered: {
      var pending = Object.assign({}, root.pendingRequests)
      var expired = []
      for (var key in pending) {
        if (pending[key].deadline <= Date.now()) { expired.push(pending[key].arguments); delete pending[key] }
      }
      root.pendingRequests = pending
      for (var i = 0; i < expired.length; ++i) root.actionFinished(expired[i], 1, "Player did not respond. This action may have completed; check playback before trying again.")
    }
  }
  Component.onCompleted: backend.running = true

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
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
    text: ""; hasVisualContent: true; labelVisible: false
    fixedWidth: root.vertical ? root.barSize : Style.space(30)
    active: root.playbackActive
    dimmed: root.playerRunning && root.playerPaused
    tooltipText: !root.statusReady ? "Skylofi · connecting to player"
      : root.actionError ? "Skylofi · " + root.actionError
      : root.playerRunning ? root.playbackLabel + " · " + root.singleLineText(root.stationName, 80)
        + (root.mixOn && root.bgName ? " + " + root.singleLineText(root.bgName, 60) : "")
      : "Skylofi · left click to play, right click to open"
    Canvas {
      id: headphones
      anchors.centerIn: parent
      width: Style.space(18); height: Style.space(18)
      property color ink: button.active ? button.activeColor : button.foreground
      onInkChanged: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.reset(); c.scale(width / 24, height / 24)
        c.strokeStyle = ink; c.lineWidth = 1.8; c.lineCap = "round"; c.lineJoin = "round"
        c.beginPath(); c.moveTo(4,15); c.lineTo(4,11); c.arc(12,11,8,Math.PI,0); c.lineTo(20,15); c.stroke()
        c.beginPath(); c.roundedRect(3,12,4,8,1.5,1.5); c.roundedRect(17,12,4,8,1.5,1.5); c.stroke()
      }
    }
    PlaybackWave {
      id: barActivity
      objectName: "barPlaybackActivity"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Style.space(2)
      width: Style.space(7); height: Style.space(7)
      active: root.playbackActive
      animate: root.animationsEnabled && root.equalizerEnabled
      visible: root.playbackActive
      ink: headphones.ink
    }
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.togglePanel()
      else if (mouseButton === Qt.MiddleButton) root.runAction(["next"])
      else root.runAction(["toggle"])
    }
    onWheelMoved: function(delta) { root.changeMasterVolume(delta) }
  }
}
