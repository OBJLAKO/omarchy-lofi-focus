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
  property int natureVolume: 25
  property bool showNatureLevels: false
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
  readonly property string audibleNature: natureLayers.filter(function(layer) {
    return layer.enabled && layer.running && layer.volume > 0
  }).map(function(layer) { return layer.id }).join(",")

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

  readonly property var backgroundOptions: {
    var out = [{ value: "off", label: "Off — no background", description: "Play the main station alone" }]
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
      root.natureVolume = clampVolume(state.nature_volume === undefined ? state.noise_volume : state.nature_volume, 25)
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
    else if (channel === "nature") root.natureVolume = value
    else if (channel === "bg") root.bgVolume = value
    root.runAction(["vol", channel, String(value)])
  }

  function clampVolume(value, fallback) {
    return Math.max(0, Math.min(100, Math.round(Number(value === undefined ? fallback : value)) || 0))
  }

  function natureLayer(id) {
    for (var layer of natureLayers) if (layer.id === id) return layer
    return { enabled: false, running: false, volume: 70 }
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
    if (opened) {
      stationsFile.reload()
      if (hostWidget) {
        if (hostWidget.statusJson) root.applyStatus(hostWidget.statusJson)
        hostWidget.refreshStatus()
      }
    }
  }

  Component {
    id: heroIcon
    Item {
      implicitWidth: Style.space(40)
      implicitHeight: Style.space(40)
      width: implicitWidth
      height: implicitHeight

      Canvas {
        id: cupCanvas
        anchors.fill: parent
        property color ink: root.isPlaying ? Color.urgent : root.contentForeground
        property real steamPhase: 0
        onInkChanged: requestPaint()
        onSteamPhaseChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        NumberAnimation on steamPhase {
          from: 0
          to: 1
          duration: 2800
          loops: Animation.Infinite
          running: root.opened && root.isPlaying
        }
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.scale(width / 40, height / 40)
          c.strokeStyle = ink
          c.lineWidth = 1.8
          c.lineCap = "round"
          c.lineJoin = "round"
          // The cup stays still; only the three steam wisps rise and fade.
          c.beginPath()
          c.moveTo(7, 18); c.lineTo(28, 18); c.lineTo(28, 27)
          c.quadraticCurveTo(28, 33, 22, 33); c.lineTo(13, 33)
          c.quadraticCurveTo(7, 33, 7, 27); c.closePath(); c.stroke()
          c.beginPath(); c.moveTo(28, 20); c.lineTo(31, 20)
          c.bezierCurveTo(39, 20, 39, 29, 28, 28); c.stroke()
          c.beginPath(); c.moveTo(5, 37); c.lineTo(33, 37); c.stroke()
          for (var i = 0; i < 3; i++) {
            var phase = (steamPhase + i / 3) % 1
            var x = 12 + i * 6
            var y = 16 - phase * 8
            var sway = Math.sin(phase * Math.PI * 2) * 1.8
            c.globalAlpha = Math.sin(phase * Math.PI) * 0.7
            c.beginPath(); c.moveTo(x, y)
            c.bezierCurveTo(x - 3 + sway, y - 2, x + 3 + sway, y - 4, x, y - 7)
            c.stroke()
          }
          c.globalAlpha = 1
        }
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: musicPicker.popupOpen || voicePicker.popupOpen
      onCloseRequested: root.close()
    }

    Flickable {
      id: panelScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(12)

        // ---- Hero: what is playing right now
        PanelHero {
          width: parent.width
          iconComponent: heroIcon
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          title: root.playerName || "Lofi Radio"
          meta: {
            var parts = []
            if (root.playerCategoryName) parts.push(root.playerCategoryName)
            parts.push(root.playerPaused ? "Paused" : (root.musicConnecting ? "Connecting music" : (root.playerRunning ? "Playing" : "Stopped")))
            if (root.stationCount > 1) parts.push((root.stationIndex + 1) + "/" + root.stationCount)
            return parts.join("  ·  ")
          }
          detail: root.musicRunning && root.isPlaying ? "LIVE" : ""
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        // ---- Transport
        Row {
          spacing: Style.space(6)

          Button {
            iconText: root.sessionActive && !root.playerPaused ? "\uf04c" : "\uf04b"
            text: root.playerPaused ? "Resume" : (root.sessionActive ? "Pause" : "Play")
            foreground: root.contentForeground
            onClicked: root.runAction(["toggle"])
          }

          Button {
            iconText: "\uf048"
            text: "Prev"
            opacity: root.stationCount > 1 ? 1 : 0.4
            foreground: root.contentForeground
            onClicked: if (root.stationCount > 1) root.runAction(["prev"])
          }

          Button {
            iconText: "\uf051"
            text: "Next"
            opacity: root.stationCount > 1 ? 1 : 0.4
            foreground: root.contentForeground
            onClicked: if (root.stationCount > 1) root.runAction(["next"])
          }

          Button {
            iconText: "\uf04d"
            text: "Stop"
            foreground: root.contentForeground
            onClicked: root.runAction(["stop"])
          }
        }

        Text {
          visible: root.musicConnecting || root.mainState === "failed"
          width: parent.width
          text: root.mainState === "failed" ? "Radio unavailable. Try another station or retry below."
            : root.mainState === "connecting" ? "Connecting to the radio…"
            : root.retryIn > 0 ? "Radio interrupted · retrying in " + root.retryIn + "s"
            : "Reconnecting to the radio…"
          textFormat: Text.PlainText
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: root.contentMuted
          wrapMode: Text.WordWrap
        }

        Button {
          visible: root.mainState === "failed"
          text: "Retry music"
          foreground: root.contentForeground
          onClicked: root.runAction(["start", root.playerStationId])
        }

        // ---- Volume
        PanelSectionHeader {
          text: "Volume"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Master"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.contentMuted
              width: Style.space(52)
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelSlider {
              width: parent.width - parent.spacing * 2 - Style.space(52) - Style.space(34)
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.masterVolume
              onReleased: function(value) { root.setVolume("master", value) }
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.masterVolume + "%"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              color: root.contentForeground
              width: Style.space(34)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Music"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.contentMuted
              width: Style.space(52)
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelSlider {
              width: parent.width - parent.spacing * 2 - Style.space(52) - Style.space(34)
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.mainVolume
              onReleased: function(value) { root.setVolume("main", value) }
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.mainVolume + "%"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              color: root.contentForeground
              width: Style.space(34)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Voice"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.contentMuted
              width: Style.space(52)
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelSlider {
              width: parent.width - parent.spacing * 2 - Style.space(52) - Style.space(34)
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.bgVolume
              enabled: root.mixOn
              opacity: root.mixOn ? 1 : 0.5
              onReleased: function(value) { root.setVolume("bg", value) }
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.bgVolume + "%"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              color: root.mixOn ? root.contentForeground : root.contentMuted
              width: Style.space(34)
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Nature"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.contentMuted
              width: Style.space(52)
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelSlider {
              width: parent.width - parent.spacing * 2 - Style.space(52) - Style.space(34)
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.natureVolume
              onReleased: function(value) { root.setVolume("nature", value) }
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.natureVolume + "%"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              color: root.contentForeground
              width: Style.space(34)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        PanelSectionHeader {
          text: "Your focus space"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        SearchableDropdown {
          width: parent.width
          id: musicPicker
          label: "Music"
          options: root.musicOptions
          value: root.playerStationId
          foreground: root.contentForeground
          placeholderText: "Choose a station…"
          onChanged: function(value) { root.runAction(["start", value]) }
        }

        SearchableDropdown {
          width: parent.width
          id: voicePicker
          label: "Background voice"
          options: root.backgroundOptions
          value: root.mixOn ? root.bgStation : "off"
          foreground: root.contentForeground
          placeholderText: "Choose a voice…"
          onChanged: function(value) { root.runAction(["bg", value]) }
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        Column {
          width: parent.width
          spacing: Style.space(4)
          PanelSectionHeader {
            text: "Nature sounds" + (root.enabledNatureCount > 0 ? " · " + root.enabledNatureCount + " selected" : "")
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }
          Text {
            width: parent.width
            text: "Pick a few sounds to layer together."
            textFormat: Text.PlainText
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            color: root.contentMuted
          }
        }

        NatureScene {
          id: natureScene
          width: parent.width
          height: Style.space(48)
          visible: root.enabledNatureCount > 0
          foreground: root.contentForeground
          accent: Color.accent
          sounds: root.audibleNature
          playing: root.opened && root.isPlaying && root.masterVolume > 0 && root.natureVolume > 0
            && y + height > panelScroll.contentY && y < panelScroll.contentY + panelScroll.height
        }

        Grid {
          id: natureGrid
          width: parent.width
          columns: 2
          spacing: Style.space(6)
          Repeater {
            model: root.noiseOptions
            Button {
              required property var modelData
              width: (natureGrid.width - natureGrid.spacing) / 2
              text: modelData.label
              iconText: selected ? "\uf00c" : "\uf067"
              iconSize: Style.font.caption
              fontSize: Style.font.bodySmall
              leftAlign: true
              bordered: true
              focusable: true
              foreground: root.contentForeground
              selected: root.natureLayer(modelData.value).enabled
              tooltipText: modelData.description || ""
              onClicked: root.runAction(["nature", modelData.value, "toggle"])
            }
          }
        }

        Button {
          visible: root.enabledNatureCount > 0
          text: root.showNatureLevels ? "Hide individual levels" : "Adjust individual levels"
          iconText: root.showNatureLevels ? "\uf106" : "\uf107"
          fontSize: Style.font.caption
          foreground: root.contentForeground
          focusable: true
          onClicked: root.showNatureLevels = !root.showNatureLevels
        }

        Column {
          width: parent.width
          visible: root.showNatureLevels && root.enabledNatureCount > 0
          spacing: Style.space(8)
          // Keep delegates stable while status updates arrive during a drag.
          Repeater {
            model: root.noiseOptions
            Row {
              required property var modelData
              readonly property var natureState: root.natureLayer(modelData.value)
              visible: natureState.enabled
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: Style.space(116)
                text: modelData.label
                textFormat: Text.PlainText
                color: root.contentMuted
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }
              PanelSlider {
                width: parent.width - parent.spacing * 2 - Style.space(116) - Style.space(34)
                bar: root.bar
                minimum: 0
                maximum: 100
                step: 5
                integer: true
                value: parent.natureState.volume
                onReleased: function(value) { root.setVolume(parent.modelData.value, value) }
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                width: Style.space(34)
                text: parent.natureState.volume + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        Row {
          width: parent.width
          spacing: Style.space(10)
          ToggleSwitch {
            checked: root.ducking
            foreground: root.contentForeground
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.runAction(["ducking", root.ducking ? "off" : "on"])
          }
          Text {
            text: "Quiet while dictating · VoxType"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---- Footer
        Text {
          width: parent.width
          text: "Your mix is saved automatically."
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: root.contentMuted
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
