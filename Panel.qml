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

  readonly property string heroStatus: root.playerPaused ? "Paused"
    : root.musicConnecting ? (root.retryIn > 0 ? "Reconnecting in " + root.retryIn + "s"
      : (root.mainState === "reconnecting" ? "Reconnecting" : "Connecting"))
    : root.playerRunning ? "Playing"
    : "Ready"

  readonly property string heroMeta: {
    var parts = []
    if (root.playerCategoryName) parts.push(root.playerCategoryName)
    if (root.mixOn && root.bgName) parts.push(root.bgName)
    if (root.enabledNatureCount > 0) parts.push(root.enabledNatureCount + (root.enabledNatureCount === 1 ? " sound" : " sounds"))
    parts.push(root.heroStatus)
    return parts.join(" · ")
  }

  readonly property string heroTitle: root.playerRunning || root.musicConnecting
    ? (root.playerName || "Lofi Focus")
    : "Lofi Focus"

  // Music stations listed on the panel, with a glyph per category.
  function categoryGlyph(id) {
    var map = { lofi: "\uf001", podcasts: "\uf130", talk: "\uf130", atc: "\uf072", ambience: "\uf0f5" }
    return map[id] || "\uf001"
  }

  readonly property var musicStations: {
    var out = []
    for (var c of categories) {
      if (c.id !== "lofi") continue
      for (var st of c.stations) out.push({
        id: st.id, name: st.name, description: st.description,
        glyph: categoryGlyph(c.id)
      })
    }
    return out
  }

  function isMusicPlaying(id) {
    return root.sessionActive && !root.playerPaused && root.playerStationId === id && root.musicRunning
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Math.min(contentColumn.implicitHeight, Style.space(620)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: voicePicker.popupOpen || naturePicker.popupOpen
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

        PanelHero {
          width: parent.width
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          title: root.heroTitle
          meta: root.heroMeta
          detail: root.stationCount > 0 ? (root.stationIndex + 1) + "/" + root.stationCount : ""
          iconOpacity: root.isPlaying ? 1.0 : 0.75
          iconComponent: Component {
            Canvas {
              width: Style.font.display
              height: Style.font.display
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
          }
          trailingControl: Component {
            Row {
              spacing: Style.space(6)
              Button {
                id: playButton
                iconText: root.sessionActive && !root.playerPaused ? "\uf04c" : "\uf04b"
                tooltipText: root.playerPaused ? "Resume" : (root.sessionActive ? "Pause" : "Play")
                foreground: root.contentForeground
                focusable: true
                onClicked: root.runAction(["toggle"])
              }
              Button {
                id: stopButton
                iconText: "\uf04d"
                tooltipText: "Stop all sounds"
                foreground: root.contentForeground
                focusable: true
                onClicked: root.runAction(["stop"])
              }
            }
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
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "STATIONS"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Repeater {
            model: root.musicStations

            StationRow {
              required property var modelData
              required property int index
              width: parent.width
              glyph: modelData.glyph
              name: modelData.name
              description: modelData.description
              current: root.playerStationId === modelData.id
              playing: root.isMusicPlaying(modelData.id)
              muted: root.playerStationId === modelData.id && root.sessionActive && root.playerPaused
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(["start", modelData.id])
              }
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

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "VOICE"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            FocusDropdown {
              id: voicePicker
              width: parent.width
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

        PanelSectionHeader {
          text: "NATURE"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
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
