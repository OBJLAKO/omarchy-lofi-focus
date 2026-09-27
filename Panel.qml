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
  property bool settingsOpen: false
  property string mainState: "stopped"
  property int retryIn: 0
  property int masterVolume: 100
  property int mainVolume: 80
  property int bgVolume: 40
  property int stationIndex: 0
  property int stationCount: 0
  property string mainTitle: ""
  property var youtubeEntries: []
  property bool youtubeAvailable: true
  property bool libraryOpen: false
  property bool savingLink: false
  property string libraryMessage: ""
  property bool libraryError: false
  readonly property var youtubeUrl: youtubeLibrary.urlField
  readonly property var youtubeTitle: youtubeLibrary.titleField
  readonly property bool youtubeSelected: playerCategory === "youtube"
  readonly property bool sourceEnded: mainState === "ended"
  property real mainPosition: -1
  property real mainDuration: -1

  // ---- Look-and-feel preferences, mirrored from status.json. They persist in
  //      the same settings.json the backend owns, so the panel and the CLI
  //      always agree on what is enabled.
  property bool animationsEnabled: true
  property bool revealEnabled: true
  property bool steamEnabled: true
  property bool glowEnabled: true
  property bool equalizerEnabled: true
  property bool fadeEnabled: true
  property int fadeSeconds: 3
  property int revealSpeed: 1
  property bool collapsibleSections: true
  property int duckLevel: 35

  // Which sections the user has collapsed, by section key. Session-only: the
  // master switch is a setting, the collapse state itself is a transient view.
  property var collapsed: ({})

  readonly property bool motionOn: animationsEnabled
  readonly property bool steamOn: motionOn && steamEnabled && isPlaying
  readonly property bool glowOn: motionOn && glowEnabled
  readonly property bool equalizerOn: motionOn && equalizerEnabled
  // Reveal is a touch slower than a snap but never sluggish; the speed slider
  // scales the base timings.
  readonly property real revealStep: 45 * revealSpeed
  readonly property int revealDuration: Math.round(240 * revealSpeed)

  readonly property bool isPlaying: playerRunning && !playerPaused && !sourceEnded
  readonly property bool musicConnecting: mainState === "connecting" || mainState === "reconnecting"
  readonly property bool sessionActive: playerRunning || musicConnecting
  readonly property int enabledNatureCount: natureLayers.filter(function(layer) { return layer.enabled }).length
  // ---- Stations
  property var categories: []

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentMuted: Qt.alpha(root.contentForeground, 0.65)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string heroStatus: root.sourceEnded ? "Finished" : root.playerPaused ? "Paused"
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

  // Progress only makes sense when the stream reports a duration: live radio
  // leaves it unset, podcasts and YouTube links do not.
  readonly property bool hasProgress: root.mainDuration > 0 && root.mainPosition >= 0
  readonly property real progressFraction: root.hasProgress
    ? Math.max(0, Math.min(1, root.mainPosition / root.mainDuration)) : 0
  readonly property string nowPlayingTitle: root.mainTitle !== "" ? root.mainTitle : root.playerName

  function formatTime(seconds) {
    if (!(seconds >= 0)) return "--:--"
    var total = Math.floor(seconds)
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    var mm = (minutes < 10 && hours > 0 ? "0" : "") + minutes
    var ss = (secs < 10 ? "0" : "") + secs
    return hours > 0 ? hours + ":" + mm + ":" + ss : mm + ":" + ss
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
      root.youtubeEntries = Array.isArray(state.youtube_entries) ? state.youtube_entries : []
      root.youtubeAvailable = state.youtube_available !== false
      root.mainTitle = String(state.main_title || "").replace(/[\r\n\t]+/g, " ").slice(0, 200)
      root.mainPosition = typeof state.main_position === "number" ? state.main_position : -1
      root.mainDuration = typeof state.main_duration === "number" ? state.main_duration : -1
      root.animationsEnabled = state.animations !== false
      root.revealEnabled = state.reveal_animations !== false
      root.steamEnabled = state.steam_animation !== false
      root.glowEnabled = state.glow_animation !== false
      root.equalizerEnabled = state.equalizer_animation !== false
      root.fadeEnabled = state.fade_enabled !== false
      root.fadeSeconds = Math.max(0, Math.min(8, Number(state.fade_seconds === undefined ? 3 : state.fade_seconds) || 0))
      root.revealSpeed = Math.max(0, Math.min(3, Number(state.reveal_speed === undefined ? 1 : state.reveal_speed) || 0))
      root.collapsibleSections = state.collapsible_sections !== false
      root.duckLevel = Math.max(0, Math.min(100, Math.round(Number(state.duck_level === undefined ? 35 : state.duck_level) || 0)))
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

  function saveYoutube() {
    if (savingLink || !youtubeUrl.text.trim()) return
    savingLink = true
    libraryMessage = ""
    runAction(["youtube-add", youtubeUrl.text.trim(), youtubeTitle.text.trim()])
  }

  function youtubeResult(args, code, message) {
    if (args[0] === "youtube-add") {
      savingLink = false
      libraryError = code !== 0
      libraryMessage = code === 0 ? "Saved to your library." : (message || "Could not save this link.")
      if (code === 0) { youtubeUrl.text = ""; youtubeTitle.text = ""; youtubeLibrary.addingLink = false }
    } else if (code !== 0) {
      libraryError = true
      libraryMessage = message || "Could not complete that action."
    }
  }

  function runAction(args) {
    if (hostWidget && typeof hostWidget.runAction === "function") hostWidget.runAction(args)
  }

  // Sections fade in from top to bottom each time a screen appears, so the
  // stack settles instead of appearing all at once. Disabled entirely by the
  // Animations settings.
  function revealSections() {
    var column = root.settingsOpen ? settingsColumn : contentColumn
    if (!column) return
    var kids = column.children
    for (var i = 0; i < kids.length; i++) {
      var item = kids[i]
      if (!item || item.opacity === undefined) continue
      if (!root.motionOn || !root.revealEnabled) { item.opacity = 1; continue }
      item.opacity = 0
      var animation = revealAnimation.createObject(column, { "item": item, "delay": i * root.revealStep })
      if (animation) animation.start()
    }
  }

  Component {
    id: revealAnimation
    SequentialAnimation {
      id: sectionReveal
      property var item: null
      property int delay: 0
      PauseAnimation { duration: sectionReveal.delay }
      NumberAnimation {
        target: sectionReveal.item
        property: "opacity"
        to: 1
        duration: root.revealDuration
        easing.type: Easing.OutCubic
      }
      ScriptAction { script: sectionReveal.destroy() }
    }
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

  function isCollapsed(key) {
    return root.collapsibleSections && root.collapsed[key] === true
  }

  function toggleCollapsed(key) {
    var next = Object.assign({}, root.collapsed)
    next[key] = !(next[key] === true)
    root.collapsed = next
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
    function onActionFinished(arguments, exitCode, message) { root.youtubeResult(arguments, exitCode, message) }
  }

  onOpenedChanged: {
    if (!opened) settingsOpen = false
    if (opened) {
      stationsFile.reload()
      if (hostWidget) {
        if (hostWidget.statusJson) root.applyStatus(hostWidget.statusJson)
        hostWidget.refreshStatus()
      }
      Qt.callLater(root.revealSections)
    }
  }

  onSettingsOpenChanged: Qt.callLater(root.revealSections)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(
      Math.min(root.settingsOpen ? settingsColumn.implicitHeight : contentColumn.implicitHeight, Style.space(620)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: voicePicker.popupOpen || naturePicker.popupOpen || youtubeUrl.activeFocus || youtubeTitle.activeFocus
      onCloseRequested: root.close()
    }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      visible: !root.settingsOpen
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        objectName: "focusContent"
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          title: "Lofi Focus"
          meta: "A little space to listen."
          detail: root.heroStatus
          iconOpacity: root.isPlaying ? 1.0 : 0.75
          iconComponent: Component {
            Item {
              id: cupIcon
              width: Style.font.display
              height: Style.font.display
              readonly property real unit: Math.min(width, height) / 24

              // Soft glow that breathes behind the cup while music is playing.
              Rectangle {
                anchors.centerIn: parent
                width: parent.width * 1.05
                height: width
                radius: width / 2
                color: Qt.alpha(Color.accent, 0.10)
                opacity: root.glowOn ? 1 : 0
                scale: 1
                Behavior on opacity { NumberAnimation { duration: 400 } }
                SequentialAnimation on scale {
                  running: root.opened && !root.settingsOpen && root.glowOn && root.isPlaying
                  loops: Animation.Infinite
                  NumberAnimation { to: 1.06; duration: 2600; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 0.94; duration: 2600; easing.type: Easing.InOutSine }
                }
              }

              // Steam: smooth translucent wisps drawn on a canvas, so they can
              // curve and drift instead of standing up as straight bars. The
              // phase advances slowly; each wisp sways and its opacity breathes,
              // which reads as rising steam without a heavy animation graph.
              Canvas {
                id: steam
                anchors.fill: parent
                visible: root.steamOn
                property real phase: 0
                onPhaseChanged: requestPaint()
                onPaint: {
                  if (!visible) return
                  var c = getContext("2d")
                  c.reset(); c.scale(width / 24, height / 24)
                  c.lineCap = "round"; c.lineJoin = "round"
                  var baseY = 7.6, topY = 0.4
                  for (var i = 0; i < 3; i++) {
                    var k = phase + i * 1.9
                    var bx = 8.6 + i * 2.4
                    var sway = Math.sin(k) * 1.25
                    var lift = (Math.sin(k * 0.6 + i) + 1) * 0.25
                    var a = 0.10 + 0.16 * (0.5 + 0.5 * Math.sin(k * 0.8 + i))
                    c.strokeStyle = "rgba(" + Math.round(Color.foreground.r * 255) + ","
                      + Math.round(Color.foreground.g * 255) + "," + Math.round(Color.foreground.b * 255) + "," + a.toFixed(3) + ")"
                    c.lineWidth = 1.05
                    c.beginPath()
                    c.moveTo(bx, baseY)
                    c.bezierCurveTo(bx + sway, baseY - (baseY - topY) * 0.4 - lift,
                                    bx - sway, topY + (baseY - topY) * 0.3,
                                    bx - sway * 0.4, topY)
                    c.stroke()
                  }
                }

                Timer {
                  interval: 40
                  running: root.opened && !root.settingsOpen && root.steamOn
                  repeat: true
                  onTriggered: steam.phase += 0.05
                }
              }

              Canvas {
                width: cupIcon.width
                height: cupIcon.height
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
          }
          trailingControl: Component {
            Row {
              spacing: Style.space(6)
              Button {
                id: playButton
                iconText: root.sessionActive && !root.playerPaused && !root.sourceEnded ? "\uf04c" : "\uf04b"
                tooltipText: root.sourceEnded ? "Replay" : root.playerPaused ? "Resume" : (root.sessionActive ? "Pause" : "Play")
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

        // Now playing: what is on, with a progress bar when the stream reports
        // a duration (podcasts and future YouTube links), plus station skip.
        BorderSurface {
          id: nowPlaying
          width: parent.width
          implicitHeight: nowPlayingContent.implicitHeight + Style.space(24)
          height: implicitHeight
          radius: Style.cornerRadius
          color: Qt.alpha(Color.accent, 0.045)
          borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)

          Column {
            id: nowPlayingContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: root.youtubeSelected ? "YOUTUBE · AUDIO" : "LIVE RADIO"
              textFormat: Text.PlainText
              color: root.contentMuted
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width - skip.width - parent.spacing
                text: root.nowPlayingTitle
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: skip
                spacing: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter

                Button {
                  iconText: "\uf048"
                  tooltipText: root.youtubeSelected && root.hasProgress ? "Back 15 seconds" : "Previous source"
                  foreground: root.contentForeground
                  focusable: true
                  onClicked: root.runAction(root.youtubeSelected && root.hasProgress ? ["seek", String(Math.max(0, root.mainPosition - 15))] : ["prev"])
                }
                Button {
                  iconText: "\uf051"
                  tooltipText: root.youtubeSelected && root.hasProgress ? "Forward 15 seconds" : "Next source"
                  foreground: root.contentForeground
                  focusable: true
                  onClicked: root.runAction(root.youtubeSelected && root.hasProgress ? ["seek", String(root.mainPosition + 15)] : ["next"])
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              visible: root.hasProgress

              Text {
                id: elapsed
                text: root.formatTime(root.mainPosition)
                textFormat: Text.PlainText
                color: root.contentMuted
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: parent.width - elapsed.width - remaining.width - parent.spacing * 2
                height: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  enabled: root.hasProgress
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) { root.runAction(["seek", String(mouse.x / width * root.mainDuration)]) }
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: height / 2
                  color: Qt.alpha(root.contentForeground, 0.14)
                }
                Rectangle {
                  width: parent.width * root.progressFraction
                  height: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: height / 2
                  color: Color.accent
                  Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
              }

              Text {
                id: remaining
                text: root.formatTime(root.mainDuration)
                textFormat: Text.PlainText
                color: root.contentMuted
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              visible: !root.hasProgress
              text: root.musicConnecting ? (root.youtubeSelected ? "Preparing audio…" : "Connecting…") : root.sourceEnded ? "Finished · press play to listen again" : root.playerCategoryName
              textFormat: Text.PlainText
              color: root.contentMuted
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        MixerLevel {
          width: parent.width
          label: "Audio"
          value: root.mainVolume
          bar: root.bar
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onEdited: function(value) { root.setVolume("main", value) }
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

        Row {
          width: parent.width
          spacing: Style.space(6)
          Button {
            width: (parent.width - parent.spacing) / 2
            text: "Radio"
            iconText: "\uf001"
            selected: !root.libraryOpen
            bordered: true
            focusable: true
            foreground: root.contentForeground
            onClicked: root.libraryOpen = false
          }
          Button {
            width: (parent.width - parent.spacing) / 2
            text: "YouTube · " + root.youtubeEntries.length
            iconText: "\uf144"
            selected: root.libraryOpen
            bordered: true
            focusable: true
            foreground: root.contentForeground
            onClicked: root.libraryOpen = true
          }
        }

        Row {
          visible: root.mainState === "failed"
          width: parent.width
          spacing: Style.space(8)
          Text {
            width: parent.width - retryButton.width - parent.spacing
            text: root.youtubeSelected ? "Could not play this video. Check the link, connection or yt-dlp update." : "Radio unavailable. Try again or choose another station."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.contentMuted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            id: retryButton
            text: "Retry"
            foreground: root.contentForeground
            focusable: true
            onClicked: root.runAction(["start", root.playerStationId])
          }
        }

        YoutubeLibrary {
          id: youtubeLibrary
          visible: root.libraryOpen
          width: parent.width
          entries: root.youtubeEntries
          selectedId: root.playerStationId
          playing: root.isPlaying && root.youtubeSelected
          foreground: root.contentForeground
          muted: root.contentMuted
          fontFamily: root.contentFontFamily
          available: root.youtubeAvailable
          saving: root.savingLink
          message: root.libraryMessage
          failed: root.libraryError
          onSaveRequested: root.saveYoutube()
          onPlayRequested: function(id) { root.runAction(["start", id]) }
          onRemoveRequested: function(id) { root.runAction(["youtube-remove", id]) }
        }

        CollapsibleSection {
          visible: !root.libraryOpen
          title: "STATIONS"
          sectionKey: "stations"
          summary: root.playerName

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
              animate: root.equalizerOn
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


        }

        PanelSeparator { visible: !root.libraryOpen && !root.youtubeSelected; width: parent.width; foreground: root.contentForeground }

        CollapsibleSection {
          visible: !root.libraryOpen && !root.youtubeSelected
          title: "VOICE"
          sectionKey: "voice"
          summary: root.mixOn && root.bgName ? root.bgName : "Off"

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

        CollapsibleSection {
          title: "YOUR ATMOSPHERE"
          sectionKey: "nature"
          summary: root.enabledNatureCount > 0
            ? root.enabledNatureCount + (root.enabledNatureCount === 1 ? " sound" : " sounds")
            : "None"

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
          text: "Appearance & playback"
          iconText: "\uf013"
          fontSize: Style.font.caption
          foreground: root.contentMuted
          focusable: true
          onClicked: root.settingsOpen = true
        }
      }
    }

    // Settings is its own screen, not an appendix to the bottom of the main
    // one: opening it replaces the whole panel so there is never any doubt
    // about scrolling further down for more controls.
    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: settingsColumn.implicitHeight
      clip: true
      visible: root.settingsOpen
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: settingsColumn
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            iconText: "\uf060"
            tooltipText: "Back to Lofi Focus"
            foreground: root.contentForeground
            focusable: true
            onClicked: root.settingsOpen = false
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)
            Text {
              text: "Settings"
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "LOOK AND FEEL"
              textFormat: Text.PlainText
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        PanelSectionHeader {
          text: "ANIMATIONS"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        SettingToggle {
          label: "Animations"
          hint: "Master switch for everything below"
          checked: root.animationsEnabled
          onToggled: root.runAction(["ui", "animations", root.animationsEnabled ? "off" : "on"])
        }
        SettingToggle {
          label: "Panel reveal"
          hint: "Sections settle in when the panel opens"
          enabled: root.animationsEnabled
          checked: root.revealEnabled
          onToggled: root.runAction(["ui", "reveal", root.revealEnabled ? "off" : "on"])
        }
        SettingToggle {
          label: "Steam"
          hint: "Wisps rising from the cup"
          enabled: root.animationsEnabled
          checked: root.steamEnabled
          onToggled: root.runAction(["ui", "steam", root.steamEnabled ? "off" : "on"])
        }
        SettingToggle {
          label: "Breathing glow"
          hint: "Soft pulse behind the cup"
          enabled: root.animationsEnabled
          checked: root.glowEnabled
          onToggled: root.runAction(["ui", "glow", root.glowEnabled ? "off" : "on"])
        }
        SettingToggle {
          label: "Station equalizer"
          hint: "Bars on the playing station"
          enabled: root.animationsEnabled
          checked: root.equalizerEnabled
          onToggled: root.runAction(["ui", "equalizer", root.equalizerEnabled ? "off" : "on"])
        }

        SettingSlider {
          label: "Reveal speed"
          value: root.revealSpeed
          minimum: 0
          maximum: 3
          step: 1
          suffix: root.revealSpeed === 0 ? "instant" : "×" + root.revealSpeed
          enabled: root.animationsEnabled && root.revealEnabled
          bar: root.bar
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onEdited: function(value) { root.runAction(["ui", "revealSpeed", String(value)]) }
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        PanelSectionHeader {
          text: "LAYOUT"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        SettingToggle {
          label: "Collapsible sections"
          hint: "Fold Stations, Voice and Nature by tapping their headers"
          checked: root.collapsibleSections
          onToggled: root.runAction(["ui", "collapsible", root.collapsibleSections ? "off" : "on"])
        }

        PanelSeparator { width: parent.width; foreground: root.contentForeground }

        PanelSectionHeader {
          text: "AUDIO"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        SettingToggle {
          label: "Fade in and out"
          hint: "Ease streams in and out instead of cutting"
          checked: root.fadeEnabled
          onToggled: root.runAction(["ui", "fade", root.fadeEnabled ? "off" : "on"])
        }
        SettingSlider {
          label: "Fade length"
          value: root.fadeSeconds
          minimum: 1
          maximum: 8
          step: 1
          suffix: root.fadeSeconds + "s"
          enabled: root.fadeEnabled
          bar: root.bar
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onEdited: function(value) { root.runAction(["ui", "fadeSeconds", String(value)]) }
        }
        SettingToggle {
          label: "Quiet while dictating · VoxType"
          hint: "Lower the mix while VoxType records"
          checked: root.ducking
          onToggled: root.runAction(["ducking", root.ducking ? "off" : "on"])
        }
        SettingSlider {
          label: "Keep audible"
          value: root.duckLevel
          minimum: 0
          maximum: 100
          step: 5
          suffix: root.duckLevel + "%"
          enabled: root.ducking
          bar: root.bar
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onEdited: function(value) { root.runAction(["ui", "duckLevel", String(value)]) }
        }
      }
    }
  }

  // One settings row: a label with an optional hint and a trailing switch.
  component SettingToggle: Row {
    id: setting
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled()
    width: parent.width
    spacing: Style.space(8)
    opacity: setting.enabled ? 1.0 : 0.45

    Column {
      width: parent.width - toggleControl.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Text {
        text: setting.label
        textFormat: Text.PlainText
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        visible: text !== ""
        text: setting.hint
        textFormat: Text.PlainText
        color: root.contentMuted
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
    ToggleSwitch {
      id: toggleControl
      checked: setting.checked
      interactive: setting.enabled
      foreground: root.contentForeground
      anchors.verticalCenter: parent.verticalCenter
      onToggled: setting.toggled()
    }
  }

  // One settings row for a numeric preference, with a right-aligned readout.
  component SettingSlider: Row {
    id: sliderRow
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property string suffix: ""
    property QtObject bar: null
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    signal edited(int value)
    width: parent.width
    spacing: Style.space(6)
    opacity: sliderRow.enabled ? 1.0 : 0.45

    Text {
      width: Style.space(96)
      text: sliderRow.label
      textFormat: Text.PlainText
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
    }
    PanelSlider {
      id: control
      width: parent.width - Style.space(96) - readout.width - parent.spacing * 2
      bar: sliderRow.bar
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      integer: true
      value: sliderRow.value
      enabled: sliderRow.enabled
      onReleased: function(value) { sliderRow.edited(value) }
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: readout
      width: Style.space(44)
      text: sliderRow.suffix
      textFormat: Text.PlainText
      color: Qt.alpha(root.contentForeground, 0.65)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // A titled section that can fold away. The whole header is a click target
  // with a hover highlight and a chevron next to the title, and collapsing is
  // animated. When the Collapsible sections setting is off, the header is
  // inert and the chevron is hidden; collapsed, it shows a short summary.
  component CollapsibleSection: Column {
    id: section
    property string title: ""
    property string summary: ""
    property string sectionKey: ""
    default property alias content: body.data
    width: parent.width
    spacing: Style.space(6)
    readonly property bool collapsed: root.isCollapsed(section.sectionKey)
    readonly property bool interactive: root.collapsibleSections

    BorderSurface {
      id: header
      width: parent.width
      // Comfortable click target, and only as tall as its contents.
      implicitHeight: headerContent.implicitHeight + Style.space(6)
      height: implicitHeight
      radius: Style.cornerRadius
      color: headerMouse.containsMouse && section.interactive
        ? Style.hoverFillFor(root.contentForeground, Color.accent)
        : "transparent"

      Row {
        id: headerContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(4)
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          id: chevron
          visible: section.interactive
          text: section.collapsed ? "\uf054" : "\uf078"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          width: section.interactive ? implicitWidth : 0
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSectionHeader {
          id: titleText
          text: section.title
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: Math.max(0, parent.width - chevron.width - titleText.width - summaryText.implicitWidth
            - parent.spacing * 3)
          height: 1
        }

        Text {
          id: summaryText
          visible: section.collapsed && section.summary !== ""
          text: section.summary
          textFormat: Text.PlainText
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: Math.min(implicitWidth, parent.width - chevron.width - titleText.width - parent.spacing * 3)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        id: headerMouse
        anchors.fill: parent
        enabled: section.interactive
        hoverEnabled: true
        cursorShape: section.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggleCollapsed(section.sectionKey)
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.space(6)
      // Animate the fold so a collapse is visible, not a jump.
      visible: !section.collapsed
      opacity: section.collapsed ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
  }
}
