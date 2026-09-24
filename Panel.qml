import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A single music station and optional background voice.
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
  property bool playerPaused: false
  property string playerStationId: ""
  property string playerName: ""
  property string playerCategory: ""
  property string playerCategoryName: ""
  property string bgStation: ""
  property string bgName: ""
  property bool mixOn: false
  property bool ducking: true
  property string noiseStation: "off"
  property int noiseVolume: 25
  property int masterVolume: 100
  property int mainVolume: 80
  property int bgVolume: 40
  property int stationIndex: 0
  property int stationCount: 0

  readonly property bool isPlaying: playerRunning && !playerPaused

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
    var out = [{ value: "off", label: "Off — no ambience" }]
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
      root.playerPaused = state.paused === true
      root.playerStationId = String(state.station || "")
      root.playerName = String(state.name || "").replace(/[\r\n\t]+/g, " ").slice(0, 120)
      root.playerCategory = String(state.category || "")
      root.playerCategoryName = String(state.category_name || "")
      root.bgStation = String(state.bg_station || "")
      root.bgName = String(state.bg_name || "")
      root.mixOn = state.mix === true
      root.noiseStation = state.noise_station || "off"
      root.noiseVolume = state.noise_volume === undefined ? 25 : state.noise_volume
      root.ducking = state.ducking !== false
      root.masterVolume = state.master_volume === undefined ? 100 : state.master_volume
      root.mainVolume = Math.max(0, Math.min(100, Math.round(Number(state.main_volume === undefined ? 80 : state.main_volume)) || 0))
      root.bgVolume = Math.max(0, Math.min(100, Math.round(Number(state.bg_volume === undefined ? 40 : state.bg_volume)) || 0))
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
    else if (channel === "noise") root.noiseVolume = value
    else root.bgVolume = value
    root.runAction(["vol", channel, String(value)])
  }

  function isCurrent(st) {
    return String(st.id || "") !== "" && String(st.id || "") === root.playerStationId
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
          running: root.opened
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
      blocked: musicPicker.popupOpen || voicePicker.popupOpen || noisePicker.popupOpen
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
        spacing: Style.space(12)

        // ---- Hero: what is playing right now
        PanelHero {
          width: parent.width
          iconComponent: heroIcon
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          title: root.playerRunning ? (root.playerName || "Playing") : "Lofi Radio"
          meta: {
            var parts = []
            if (root.playerCategoryName) parts.push(root.playerCategoryName)
            parts.push(root.playerRunning ? (root.playerPaused ? "Paused" : "Playing") : "Stopped")
            if (root.stationCount > 1) parts.push((root.stationIndex + 1) + "/" + root.stationCount)
            return parts.join("  ·  ")
          }
          detail: root.isPlaying ? "LIVE" : ""
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        // ---- Transport
        Row {
          spacing: Style.space(6)

          Button {
            iconText: root.playerRunning && !root.playerPaused ? "\uf04c" : "\uf04b"
            text: root.playerRunning ? (root.playerPaused ? "Resume" : "Pause") : "Play"
            foreground: root.contentForeground
            onClicked: root.runAction([root.playerRunning ? "toggle" : "play"])
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
              width: parent.width - parent.spacing - Style.space(52) - Style.space(34)
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
              width: parent.width - parent.spacing - Style.space(52) - Style.space(34)
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
              width: parent.width - parent.spacing - Style.space(52) - Style.space(34)
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
              width: parent.width - parent.spacing - Style.space(52) - Style.space(34)
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.noiseVolume
              onReleased: function(value) { root.setVolume("noise", value) }
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.noiseVolume + "%"
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

        SearchableDropdown {
          id: noisePicker
          width: parent.width
          label: "Nature sounds"
          options: root.noiseOptions
          value: root.noiseStation
          foreground: root.contentForeground
          onChanged: function(value) { root.runAction(["noise", value]) }
        }

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
          text: "One station. A little company. Time to focus."
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          color: root.contentMuted
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
