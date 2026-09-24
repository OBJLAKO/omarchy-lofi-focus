import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One music station, an optional voice, and a small personal nature mix.
Panel {
  id: root
  moduleName: "sky.lofi"
  ipcTarget: "sky.lofi"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Player state, mirrored from status.json
  property bool playerRunning: false
  property bool musicRunning: false
  property bool playerPaused: false
  property string playerStationId: ""
  property string playerName: ""
  property string playerCategory: ""
  property string playerCategoryName: ""
  property string bgStation: ""
  property string bgName: ""
  property bool mixOn: false
  property bool ducking: true
  property var natureLayers: []
  property bool settingsExpanded: false
  property string mainState: "stopped"
  property int retryIn: 0
  property int masterVolume: 100
  property int mainVolume: 80
  property int bgVolume: 40
  property int stationIndex: 0
  property int stationCount: 0

  readonly property bool isPlaying: playerRunning && !playerPaused
  readonly property bool musicConnecting: mainState === "connecting" || mainState === "reconnecting"
  readonly property bool sessionActive: playerRunning || musicConnecting
  readonly property int enabledNatureCount: natureLayers.filter(function(layer) { return layer.enabled }).length
  // ---- Stations
  property var categories: []

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentMuted: bar ? Qt.alpha(bar.foreground, 0.55) : Color.muted
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var musicOptions: {
    var out = []
    for (var c of categories) {
      if (c.id !== "lofi") continue
      for (var st of c.stations) out.push({ value: st.id, label: st.name, description: st.description })
    }
    return out
  }

  readonly property var noiseOptions: {
    var out = []
    for (var c of categories) {
      if (c.id !== "ambience") continue
      for (var st of c.stations) out.push({ value: st.id, label: st.name, description: st.description })
    }
    return out
  }

  readonly property var availableSounds: noiseOptions.filter(function(sound) {
    return !root.natureLayer(sound.value).enabled
  })

  readonly property var backgroundOptions: {
    var out = [{ value: "off", label: "Off", description: "No background voice" }]
    for (var i = 0; i < categories.length; i++) {
      if (categories[i].id === "lofi" || categories[i].id === "ambience") continue
      var st = categories[i].stations || []
      for (var j = 0; j < st.length; j++) {
        out.push({
          value: String(st[j].id || ""),
          label: String(st[j].name || ""),
          description: String(st[j].description || categories[i].name || "")
        })
      }
    }
    return out
  }

  function applyStatus(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var state = JSON.parse(raw)
      if (typeof state.running !== "boolean" || typeof state.paused !== "boolean") return
      root.playerRunning = state.running === true
      root.musicRunning = state.main_running === undefined ? root.playerRunning : state.main_running === true
      root.playerPaused = state.paused === true
      root.playerStationId = String(state.station || "")
      root.playerName = String(state.name || "").replace(/[\r\n\t]+/g, " ").slice(0, 120)
      root.playerCategory = String(state.category || "")
      root.playerCategoryName = String(state.category_name || "")
      root.bgStation = String(state.bg_station || "")
      root.bgName = String(state.bg_name || "")
      root.mixOn = state.mix === true
      root.natureLayers = Array.isArray(state.nature_layers) ? state.nature_layers : []
      root.mainState = String(state.main_state || (root.musicRunning ? (root.playerPaused ? "paused" : "playing") : "stopped"))
      root.retryIn = Math.max(0, Math.round(Number(state.retry_in) || 0))
      root.ducking = state.ducking !== false
      root.masterVolume = clampVolume(state.master_volume, 100)
      root.mainVolume = clampVolume(state.main_volume, 80)
      root.bgVolume = clampVolume(state.bg_volume, 40)
      root.stationIndex = Math.max(0, Math.round(Number(state.index === undefined ? 0 : state.index)) || 0)
      root.stationCount = Math.max(0, Math.round(Number(state.count === undefined ? 0 : state.count)) || 0)
    } catch (error) {
      console.warn("Lofi status parse:", String(error))
      return
    }
  }

  function loadStations(raw) {
    try {
      var data = JSON.parse(raw || "{}")
      root.categories = Array.isArray(data.categories) ? data.categories : []
    } catch (error) {
      root.categories = []
    }
  }

  function runAction(args) {
    if (hostWidget && typeof hostWidget.runAction === "function") hostWidget.runAction(args)
  }

  function setVolume(channel, value) {
    if (channel === "master") root.masterVolume = value
    else if (channel === "main") root.mainVolume = value
    else if (channel === "bg") root.bgVolume = value
    else {
      var updated = root.natureLayers.slice()
      for (var i = 0; i < updated.length; i++) {
        if (updated[i].id === channel) updated[i] = Object.assign({}, updated[i], { volume: value })
      }
      root.natureLayers = updated
    }
    root.runAction(["vol", channel, String(value)])
  }

  function clampVolume(value, fallback) {
    return Math.max(0, Math.min(100, Math.round(Number(value === undefined ? fallback : value)) || 0))
  }

  function natureLayer(id) {
    for (var layer of natureLayers) if (layer.id === id) return layer
    return { enabled: false, running: false, volume: 25 }
  }

  // ---- Data files
  FileView {
    id: stationsFile
    path: Qt.resolvedUrl("stations.json").toString().replace(/^file:\/\//, "")
    watchChanges: true
    printErrors: false
    onLoaded: root.loadStations(text())
    onFileChanged: reload()
  }

  Connections {
    target: root.hostWidget
    function onStatusJsonChanged() { root.applyStatus(root.hostWidget.statusJson) }
  }

  onOpenedChanged: {
    if (!opened) settingsExpanded = false
    if (opened) {
      stationsFile.reload()
      if (hostWidget) {
        if (hostWidget.statusJson) root.applyStatus(hostWidget.statusJson)
        hostWidget.refreshStatus()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(Math.min(contentColumn.implicitHeight, Style.space(520)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: musicPicker.popupOpen || voicePicker.popupOpen || naturePicker.popupOpen
      onCloseRequested: root.close()
    }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(8)
          Canvas {
            width: Style.space(26)
            height: Style.space(26)
            anchors.verticalCenter: parent.verticalCenter
            property color ink: root.isPlaying ? Color.urgent : root.contentForeground
            onInkChanged: requestPaint()
            onPaint: {
              var c = getContext("2d")
              c.reset(); c.scale(width / 24, height / 24)
              c.strokeStyle = ink; c.lineWidth = 1.6; c.lineCap = "round"; c.lineJoin = "round"
              c.beginPath(); c.moveTo(4,8); c.lineTo(16,8); c.lineTo(16,14)
              c.quadraticCurveTo(16,18,12,18); c.lineTo(8,18); c.quadraticCurveTo(4,18,4,14); c.closePath(); c.stroke()
              c.beginPath(); c.moveTo(16,9); c.lineTo(18,9); c.bezierCurveTo(23,9,23,15,16,15); c.stroke()
              c.beginPath(); c.moveTo(3,21); c.lineTo(21,21); c.moveTo(8,5); c.lineTo(8,3); c.moveTo(13,5); c.lineTo(13,3); c.stroke()
            }
          }
          Column {
            width: parent.width - Style.space(26) - playButton.width - stopButton.width - parent.spacing * 3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: "Lofi Focus"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: root.playerPaused ? "Paused" : (root.musicConnecting ? "Connecting…" : (root.playerRunning ? "Playing" : "Ready"))
              color: root.contentMuted
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Button {
            id: playButton
            text: root.playerPaused ? "Resume" : (root.sessionActive ? "Pause" : "Play")
            iconText: root.sessionActive && !root.playerPaused ? "\uf04c" : "\uf04b"
            foreground: root.contentForeground
            focusable: true
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.runAction(["toggle"])
          }
          Button {
            id: stopButton
            iconText: "\uf04d"
            tooltipText: "Stop all sounds"
            foreground: root.contentForeground
            focusable: true
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.runAction(["stop"])
          }
        }

        MixerLevel {
          width: parent.width
          label: "Master"
          value: root.masterVolume
          bar: root.bar
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onEdited: function(value) { root.setVolume("master", value) }
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        Column {
          width: parent.width
          spacing: Style.space(3)
          Row {
            width: parent.width
            spacing: Style.space(6)
            Text {
              width: Style.space(52)
              text: "Music"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
            FocusDropdown {
              id: musicPicker
              width: parent.width - Style.space(52) - parent.spacing
              showLabel: false
              options: root.musicOptions
              value: root.playerStationId
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              placeholderText: "Choose a station…"
              onChanged: function(value) { root.runAction(["start", value]) }
            }
          }
          MixerLevel {
            width: parent.width
            value: root.mainVolume
            bar: root.bar
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onEdited: function(value) { root.setVolume("main", value) }
          }
          Row {
            visible: root.musicConnecting || root.mainState === "failed"
            width: parent.width
            spacing: Style.space(6)
            Text {
              width: parent.width - (retryButton.visible ? retryButton.width + parent.spacing : 0)
              text: root.mainState === "failed" ? "Radio unavailable"
                : root.retryIn > 0 ? "Reconnecting in " + root.retryIn + "s…" : "Connecting to the radio…"
              textFormat: Text.PlainText
              color: root.contentMuted
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            Button {
              id: retryButton
              visible: root.mainState === "failed"
              text: "Retry"
              fontSize: Style.font.caption
              foreground: root.contentForeground
              focusable: true
              onClicked: root.runAction(["start", root.playerStationId])
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(3)
          Row {
            width: parent.width
            spacing: Style.space(6)
            Text {
              width: Style.space(52)
              text: "Voice"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
            FocusDropdown {
              id: voicePicker
              width: parent.width - Style.space(52) - parent.spacing
              showLabel: false
              options: root.backgroundOptions
              value: root.mixOn ? root.bgStation : "off"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              placeholderText: "Choose a voice…"
              onChanged: function(value) { root.runAction(["bg", value]) }
            }
          }
          MixerLevel {
            visible: root.mixOn
            width: parent.width
            value: root.bgVolume
            bar: root.bar
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onEdited: function(value) { root.setVolume("bg", value) }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        Text {
          text: "Nature"
          color: root.contentMuted
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          visible: root.enabledNatureCount > 0
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            // Stable delegates keep a dragged slider alive across status updates.
            model: root.noiseOptions
            MixerLevel {
              required property var modelData
              readonly property var soundState: root.natureLayer(modelData.value)
              visible: soundState.enabled
              width: parent.width
              label: modelData.label
              labelWidth: Style.space(108)
              value: soundState.volume
              removable: true
              bar: root.bar
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onEdited: function(value) { root.setVolume(modelData.value, value) }
              onRemoveRequested: root.runAction(["nature", modelData.value, "off"])
            }
          }
        }

        FocusDropdown {
          id: naturePicker
          width: parent.width
          visible: root.availableSounds.length > 0
          showLabel: false
          triggerLabel: "+ Add sound"
          placeholderText: "Find a sound…"
          options: root.availableSounds
          value: ""
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onChanged: function(value) {
            root.runAction(["nature", value, "on"])
            Qt.callLater(function() { naturePicker.value = "" })
          }
        }

        Button {
          text: root.settingsExpanded ? "Hide settings" : "Settings"
          iconText: root.settingsExpanded ? "\uf106" : "\uf013"
          fontSize: Style.font.caption
          foreground: root.contentMuted
          focusable: true
          onClicked: root.settingsExpanded = !root.settingsExpanded
        }
        Row {
          visible: root.settingsExpanded
          width: parent.width
          spacing: Style.space(8)
          ToggleSwitch {
            checked: root.ducking
            foreground: root.contentForeground
            onToggled: root.runAction(["ducking", root.ducking ? "off" : "on"])
          }
          Text {
            text: "Quiet while dictating · VoxType"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
