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
  property string bgState: "stopped"
  property string bgError: ""
  property bool mixOn: false
  property bool ducking: true
  property var natureLayers: []
  property bool settingsOpen: false
  property bool mixerOpen: false
  readonly property int currentView: settingsOpen ? 2 : mixerOpen ? 1 : 0
  function showView(index) {
    settingsOpen = index === 2
    mixerOpen = index === 1
  }
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
  property string actionMessage: ""
  readonly property var youtubeUrl: youtubeLibrary.urlField
  readonly property var youtubeTitle: youtubeLibrary.titleField
  readonly property bool youtubeSelected: playerCategory === "youtube"
  readonly property bool sourceEnded: mainState === "ended"
  property real mainPosition: -1
  property real mainDuration: -1

  // Existing preferences remain readable during upgrades. Only purposeful
  // motion and audio controls are exposed in the new interface.
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
  readonly property bool liveMotion: motionOn && opened
  readonly property bool steamOn: false
  readonly property bool glowOn: false
  readonly property bool equalizerOn: motionOn && equalizerEnabled
  // Reveal is a touch slower than a snap but never sluggish; the speed slider
  // scales the base timings.
  readonly property real revealStep: 45 * revealSpeed
  readonly property int revealDuration: Math.round(160 * revealSpeed)

  readonly property bool isPlaying: playerRunning && !playerPaused && !sourceEnded
  readonly property bool musicConnecting: mainState === "connecting" || mainState === "reconnecting"
  readonly property bool sessionActive: playerRunning || musicConnecting
  readonly property bool voiceLoading: mixOn && !youtubeSelected && bgState === "loading"
  readonly property bool voiceFailed: mixOn && !youtubeSelected && !voiceLoading && bgState !== "playing" && bgError.length > 0
  readonly property string voiceMessage: voiceLoading ? "Loading podcast…" : voiceFailed ? bgError : ""
  readonly property int enabledNatureCount: natureLayers.filter(function(layer) { return layer.enabled }).length
  // ---- Stations
  property var categories: []

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentMuted: Qt.alpha(root.contentForeground, 0.72)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string heroStatus: root.sourceEnded ? "Finished" : root.playerPaused ? "Paused"
    : root.musicConnecting ? (root.retryIn > 0 ? "Reconnecting in " + root.retryIn + "s"
      : (root.mainState === "reconnecting" ? "Reconnecting" : "Connecting"))
    : root.mainState === "failed" ? "Source unavailable"
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
    ? (root.playerName || "Skylofi")
    : "Skylofi"

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
  readonly property string nowPlayingTitle: root.mainTitle || root.playerName || "Choose your soundtrack"

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
      root.bgState = String(state.bg_state || (state.bg_running === true ? "playing" : "stopped"))
      var backgroundError = typeof state.bg_error === "string" ? state.bg_error
        : typeof state.error === "string" && state.error.indexOf("Podcast unavailable:") === 0 ? state.error : ""
      root.bgError = backgroundError.replace(/[\r\n\t]+/g, " ").slice(0, 300)
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

  function setVolume(channel, value) {
    value = clampVolume(value, 0)
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
  function isCollapsed(key) { return root.collapsibleSections && root.collapsed[key] === true }
  function ensureVisible(scroll, item) {
    var point = item.mapToItem(scroll.contentItem, 0, 0)
    var target = scroll.contentY
    if (point.y < target) target = point.y
    else if (point.y + item.height > target + scroll.height) target = point.y + item.height - scroll.height
    scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, target))
  }
  function toggleCollapsed(key) {
    var next = Object.assign({}, root.collapsed)
    next[key] = !(next[key] === true)
    root.collapsed = next
  }

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
    function onActionFinished(arguments, exitCode, message) {
      root.youtubeResult(arguments, exitCode, message)
      if (arguments[0] !== "youtube-add") root.actionMessage = exitCode !== 0 ? message : ""
    }
  }
  onOpenedChanged: {
    if (!opened) { voicePicker.close(); naturePicker.close() }
    else {
      if (hostWidget && hostWidget.statusJson) root.applyStatus(hostWidget.statusJson)
      Qt.callLater(root.animatePage)
    }
  }
  function animatePage() {
    if (root.liveMotion && root.revealEnabled && root.revealDuration > 0) pageReveal.restart()
    else { pageReveal.stop(); pages.opacity = 1 }
  }
  onCurrentViewChanged: Qt.callLater(root.animatePage)
  onLibraryOpenChanged: Qt.callLater(root.animatePage)
  NumberAnimation { id: pageReveal; target: pages; property: "opacity"; from: 0.6; to: 1; duration: root.revealDuration; easing.type: Easing.OutCubic }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(Style.space(640))

    // Native Tab order and control-local arrows. Escape closes transient views
    // first; a second Escape dismisses the whole panel.
    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (voicePicker.popupOpen) voicePicker.close()
          else if (naturePicker.popupOpen) naturePicker.close()
          else if (youtubeLibrary.addingLink) youtubeLibrary.addingLink = false
          else if (root.currentView !== 0) root.showView(0)
          else root.close()
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          root.showView(0)
          root.libraryOpen ? youtubeLibrary.focusSearch() : stationSearch.forceActiveFocus()
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
          root.showView(event.key - Qt.Key_1)
          event.accepted = true
        }
      }

      Column {
        id: chrome
        width: parent.width
        spacing: Style.space(14)

        Row {
          width: parent.width
          height: Style.space(34)
          spacing: Style.space(10)
          Column {
            width: parent.width - closeButton.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              text: "Skylofi"
              color: root.contentForeground; textFormat: Text.PlainText
              font.family: root.contentFontFamily; font.pixelSize: Style.font.title; font.bold: true
            }
            Text {
              text: "Sound for your space"
              color: root.contentMuted; textFormat: Text.PlainText
              font.family: root.contentFontFamily; font.pixelSize: Style.font.caption
            }
          }
          Button {
            id: closeButton
            iconText: "\uf00d"
            tooltipText: "Close panel · Esc"
            foreground: root.contentMuted
            width: Style.space(32); height: Style.space(32)
            horizontalPadding: 0; verticalPadding: 0
            focusable: true
            Accessible.name: "Close panel"
            onClicked: root.close()
          }
        }

        BorderSurface {
          id: nowPlaying
          visible: root.currentView !== 2
          width: parent.width
          height: nowCopy.implicitHeight + Style.space(28)
          radius: Style.cornerRadius
          color: Qt.alpha(Color.accent, root.isPlaying ? 0.08 : 0.035)
          borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)
          Behavior on color { enabled: root.liveMotion; ColorAnimation { duration: 180 } }
          Column {
            id: nowCopy
            anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(14)
            spacing: Style.space(10)
            Row {
              width: parent.width
              spacing: Style.space(7)
              Rectangle {
                width: Style.space(6); height: width; radius: width / 2
                color: root.mainState === "failed" ? Color.urgent : root.isPlaying ? Color.accent : root.contentMuted
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: root.heroStatus + (root.playerCategoryName ? " · " + root.playerCategoryName : "")
                textFormat: Text.PlainText; color: root.contentMuted
                font.family: root.contentFontFamily; font.pixelSize: Style.font.caption
              }
              Item { width: Math.max(0, parent.width - parent.children[0].width - parent.children[1].width - activity.width - parent.spacing * 3); height: 1 }
              PlaybackWave {
                id: activity
                width: Style.space(14); height: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                active: root.isPlaying
                animate: root.liveMotion && root.equalizerEnabled
                ink: Color.accent
              }
            }
            Text {
              width: parent.width
              text: root.nowPlayingTitle; textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily; font.pixelSize: Style.font.title; font.bold: true
              elide: Text.ElideRight
              maximumLineCount: 1
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              Button {
                objectName: "previousSource"
                width: Style.space(36); height: Style.space(36)
                iconText: "\uf048"
                tooltipText: root.youtubeSelected && root.hasProgress ? "Back 15 seconds" : "Previous source"
                foreground: root.contentForeground; focusable: true
                onClicked: root.runAction(root.youtubeSelected && root.hasProgress ? ["seek", String(Math.max(0, root.mainPosition - 15))] : ["prev"])
              }
              Button {
                objectName: "togglePlayback"
                text: root.sourceEnded ? "Replay" : root.playerPaused ? "Resume" : root.sessionActive ? "Pause" : "Play"
                iconText: root.sessionActive && !root.playerPaused && !root.sourceEnded ? "\uf04c" : "\uf04b"
                selected: true
                width: Style.space(106); height: Style.space(36)
                foreground: root.contentForeground; focusable: true
                onClicked: root.runAction(["toggle"])
              }
              Button {
                objectName: "nextSource"
                width: Style.space(36); height: Style.space(36)
                iconText: "\uf051"
                tooltipText: root.youtubeSelected && root.hasProgress ? "Forward 15 seconds" : "Next source"
                foreground: root.contentForeground; focusable: true
                onClicked: root.runAction(root.youtubeSelected && root.hasProgress ? ["seek", String(Math.min(root.mainDuration, root.mainPosition + 15))] : ["next"])
              }
              Item { width: Math.max(0, parent.width - Style.space(214) - parent.spacing * 4); height: 1 }
              Button {
                objectName: "stopPlayback"
                width: Style.space(36); height: Style.space(36)
                iconText: "\uf04d"; tooltipText: "Stop all sounds"
                enabled: root.sessionActive
                opacity: enabled ? 1 : 0.45
                foreground: root.contentMuted; focusable: true
                onClicked: root.runAction(["stop"])
              }
            }
            Column {
              visible: root.hasProgress
              width: parent.width
              spacing: Style.space(2)
              PanelSlider {
                objectName: "playbackProgress"
                width: parent.width
                minimum: 0; maximum: Math.max(1, root.mainDuration); step: 15
                value: Math.max(0, root.mainPosition)
                trackColor: Qt.alpha(root.contentForeground, 0.16)
                fillColor: Color.accent; knobColor: Color.accent
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider; Accessible.name: "Playback position"
                Keys.onLeftPressed: root.runAction(["seek", String(Math.max(0, root.mainPosition - 15))])
                Keys.onRightPressed: root.runAction(["seek", String(Math.min(root.mainDuration, root.mainPosition + 15))])
                onReleased: function(value) { root.runAction(["seek", String(value)]) }
              }
              Row {
                width: parent.width
                Text { width: parent.width / 2; text: root.formatTime(root.mainPosition); color: root.contentMuted; font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                Text { width: parent.width / 2; text: root.formatTime(root.mainDuration); color: root.contentMuted; horizontalAlignment: Text.AlignRight; font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
              }
            }
            Row {
              visible: root.mainState === "failed"
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: parent.width - retryButton.width - parent.spacing
                text: root.youtubeSelected ? "This link could not play. Try again or choose another source." : "Source unavailable. Try again or choose another station."
                wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: root.contentMuted; font.family: root.contentFontFamily; font.pixelSize: Style.font.caption
              }
              Button {
                id: retryButton
                text: "Retry"; foreground: root.contentForeground; focusable: true
                onClicked: root.runAction(["start", root.playerStationId])
              }
            }
          }
        }
        MixerLevel {
          visible: root.currentView !== 2
          width: parent.width
          label: "Master"
          value: root.masterVolume
          bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
          onEdited: function(value) { root.setVolume("master", value) }
        }
        Row {
          id: tabs
          objectName: "mainNavigation"
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: ["Listen", "Mix", "Settings"]
            Button {
              required property string modelData
              required property int index
              objectName: "mainTab-" + index
              width: (tabs.width - 2 * tabs.spacing) / 3
              height: Style.space(36)
              text: modelData
              selected: root.currentView === index
              focusable: true
              foreground: root.contentForeground
              Accessible.name: modelData
              onClicked: root.showView(index)
            }
          }
        }
        PanelSeparator { width: parent.width; foreground: root.contentForeground }
        Caption { visible: text.length > 0; text: root.actionMessage; color: Color.urgent }
      }

      Item {
        id: pages
        anchors.top: chrome.bottom; anchors.topMargin: Style.space(14)
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        clip: true
        Flickable {
          id: listenScroll
          anchors.fill: parent
          contentWidth: width; contentHeight: contentColumn.implicitHeight
          clip: true; visible: root.currentView === 0
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          Column {
            id: contentColumn
            objectName: "focusContent"
            width: parent.width
            spacing: Style.space(12)
            Row {
              width: parent.width
              spacing: Style.space(6)
              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Radio"; iconText: "\uf001"
                selected: !root.libraryOpen; bordered: true; focusable: true
                foreground: root.contentForeground
                onClicked: root.libraryOpen = false
              }
              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Saved links · " + root.youtubeEntries.length; iconText: "\uf144"
                selected: root.libraryOpen; bordered: true; focusable: true
                foreground: root.contentForeground
                onClicked: root.libraryOpen = true
              }
            }
            TextField {
              id: stationSearch
              objectName: "stationSearch"
              width: parent.width
              visible: !root.libraryOpen
              placeholderText: "Search stations"
              foreground: root.contentForeground
              maximumLength: 160
              Keys.onEscapePressed: { text = ""; focus = false }
            }
            Column {
              visible: !root.libraryOpen
              width: parent.width
              spacing: Style.space(2)
              Repeater {
                model: root.musicStations
                StationRow {
                  required property var modelData
                  objectName: "station-" + modelData.id
                  width: parent.width
                  visible: !root.isCollapsed("stations") && (modelData.name + " " + modelData.description).toLowerCase().indexOf(stationSearch.text.trim().toLowerCase()) >= 0
                  glyph: modelData.glyph; name: modelData.name; description: modelData.description
                  current: root.playerStationId === modelData.id
                  playing: root.isMusicPlaying(modelData.id)
                  muted: root.playerPaused
                  animate: root.liveMotion && root.equalizerEnabled && root.currentView === 0 && !root.libraryOpen
                  foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  onActivated: root.runAction(["start", modelData.id])
                  onActiveFocusChanged: if (activeFocus) root.ensureVisible(listenScroll, this)
                }
              }
              Text {
                visible: stationSearch.text.length > 0 && root.musicStations.filter(function(st) { return (st.name + " " + st.description).toLowerCase().indexOf(stationSearch.text.trim().toLowerCase()) >= 0 }).length === 0
                width: parent.width
                text: "No stations found. Try another search."
                color: root.contentMuted; font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
              }
            }
            YoutubeLibrary {
              id: youtubeLibrary
              objectName: "youtubeLibrary"
              visible: root.libraryOpen
              width: parent.width
              entries: root.youtubeEntries; selectedId: root.playerStationId
              playing: root.isPlaying && root.youtubeSelected
              animate: root.liveMotion && root.equalizerEnabled && root.currentView === 0
              foreground: root.contentForeground; muted: root.contentMuted; fontFamily: root.contentFontFamily
              available: root.youtubeAvailable; saving: root.savingLink
              message: root.libraryMessage; failed: root.libraryError
              onSaveRequested: root.saveYoutube()
              onPlayRequested: function(id) { root.runAction(["start", id]) }
              onRemoveRequested: function(id) { root.runAction(["youtube-remove", id]) }
            }
          }
        }

        Flickable {
          id: mixerScroll
          anchors.fill: parent
          contentWidth: width; contentHeight: mixColumn.implicitHeight
          visible: root.currentView === 1; clip: true
          boundsBehavior: Flickable.StopAtBounds; interactive: contentHeight > height
          Column {
            id: mixColumn
            width: parent.width
            spacing: Style.space(16)
            Column {
              width: parent.width; spacing: Style.space(4)
              PageTitle { text: "Your mix" }
              Caption { text: "Balance your soundtrack, voice and atmosphere." }
            }
            MixerLevel {
              objectName: "soundtrackLevel"
              width: parent.width
              label: "Soundtrack"; labelWidth: Style.space(108); value: root.mainVolume
              bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
              onEdited: function(value) { root.setVolume("main", value) }
            }
            PanelSeparator { width: parent.width; foreground: root.contentForeground }
            Column {
              width: parent.width; spacing: Style.space(8)
              SectionTitle { text: "Voice & conversations" }
              Caption { visible: root.youtubeSelected; text: "Voice is paused while YouTube plays. It returns when you switch to radio." }
              FocusDropdown {
                id: voicePicker
                objectName: "voicePicker"
                width: parent.width
                showLabel: false; options: root.backgroundOptions
                animate: root.liveMotion
                value: root.mixOn ? root.bgStation : "off"
                enabled: !root.youtubeSelected
                opacity: enabled ? 1 : 0.5
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                placeholderText: "Search voices and podcasts"
                onChanged: function(value) { root.runAction(["bg", value]) }
              }
              Row {
                width: parent.width
                visible: root.voiceMessage.length > 0
                spacing: Style.space(8)
                Caption {
                  objectName: "voiceStatus"
                  width: parent.width - (voiceRetry.visible ? voiceRetry.width + parent.spacing : 0)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.voiceMessage
                  color: root.voiceFailed ? Color.urgent : root.contentMuted
                }
                Button {
                  id: voiceRetry
                  objectName: "voiceRetry"
                  visible: root.voiceFailed && root.bgStation.length > 0
                  text: "Retry"; foreground: root.contentForeground; focusable: true
                  onClicked: root.runAction(["bg", root.bgStation])
                }
              }
              MixerLevel {
                visible: root.mixOn && !root.youtubeSelected
                width: parent.width
                label: "Voice"; labelWidth: Style.space(108); value: root.bgVolume
                bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                onEdited: function(value) { root.setVolume("bg", value) }
              }
            }
            PanelSeparator { width: parent.width; foreground: root.contentForeground }
            Column {
              width: parent.width; spacing: Style.space(10)
              Row {
                width: parent.width; spacing: Style.space(8)
                SectionTitle { width: parent.width - naturePicker.width - parent.spacing; text: "Atmosphere · " + root.enabledNatureCount; anchors.verticalCenter: parent.verticalCenter }
                FocusDropdown {
                  id: naturePicker
                  objectName: "naturePicker"
                  width: Style.space(150)
                  visible: root.availableSounds.length > 0
                  showLabel: false; triggerLabel: "+ Add sound"
                  showDescriptions: false; animate: root.liveMotion
                  placeholderText: "Search nature sounds"
                  options: root.availableSounds; value: ""
                  foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  onChanged: function(value) {
                    root.runAction(["nature", value, "on"])
                    Qt.callLater(function() { naturePicker.value = "" })
                  }
                }
              }
              Caption { visible: root.enabledNatureCount === 0; text: "Add rain, a fireplace or a little ocean. Every sound has its own level." }
              Item {
                id: natureBody
                objectName: "section-body-nature"
                width: parent.width
                height: root.isCollapsed("nature") ? 0 : natureColumn.implicitHeight
                clip: true
                Behavior on height { enabled: root.liveMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Column {
                  id: natureColumn
                  width: parent.width; spacing: Style.space(8)
                  Repeater {
                    model: root.noiseOptions
                    MixerLevel {
                      required property var modelData
                      readonly property var soundState: root.natureLayer(modelData.value)
                      visible: soundState.enabled
                      width: parent.width
                      label: modelData.label; labelWidth: Style.space(108); value: soundState.volume
                      removable: true
                      bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                      onEdited: function(value) { root.setVolume(modelData.value, value) }
                      onRemoveRequested: root.runAction(["nature", modelData.value, "off"])
                    }
                  }
                }
              }
            }
          }
        }

        Flickable {
          id: settingsScroll
          anchors.fill: parent
          contentWidth: width; contentHeight: settingsColumn.implicitHeight
          visible: root.currentView === 2; clip: true
          boundsBehavior: Flickable.StopAtBounds; interactive: contentHeight > height
          Column {
            id: settingsColumn
            width: parent.width; spacing: Style.space(18)
            PageTitle { text: "Settings" }
            Column {
              width: parent.width; spacing: Style.space(10)
              SectionTitle { text: "Playback" }
              SettingToggle {
                label: "Gentle start & stop"
                hint: "Ease the mix in and out."
                checked: root.fadeEnabled
                onToggled: root.runAction(["ui", "fade", root.fadeEnabled ? "off" : "on"])
              }
              SettingSlider {
                visible: root.fadeEnabled
                label: "Fade duration"; value: root.fadeSeconds
                minimum: 1; maximum: 8; step: 1; suffix: root.fadeSeconds + "s"
                onEdited: function(value) { root.runAction(["ui", "fadeSeconds", String(value)]) }
              }
            }
            PanelSeparator { width: parent.width; foreground: root.contentForeground }
            Column {
              width: parent.width; spacing: Style.space(10)
              SectionTitle { text: "Focus" }
              SettingToggle {
                label: "Quiet while dictating"
                hint: "Lower every sound while VoxType records."
                checked: root.ducking
                onToggled: root.runAction(["ducking", root.ducking ? "off" : "on"])
              }
              SettingSlider {
                visible: root.ducking
                label: "Keep audible"; value: root.duckLevel
                minimum: 0; maximum: 100; step: 5; suffix: root.duckLevel + "%"
                onEdited: function(value) { root.runAction(["ui", "duckLevel", String(value)]) }
              }
            }
            PanelSeparator { width: parent.width; foreground: root.contentForeground }
            Column {
              width: parent.width; spacing: Style.space(10)
              SectionTitle { text: "Appearance" }
              SettingToggle {
                label: "Interface motion"
                hint: "Brief transitions when controls change."
                checked: root.animationsEnabled
                onToggled: root.runAction(["ui", "animations", root.animationsEnabled ? "off" : "on"])
              }
              SettingToggle {
                label: "Playback indicator"
                hint: "A small moving mark while audio plays."
                enabled: root.animationsEnabled
                checked: root.equalizerEnabled
                onToggled: root.runAction(["ui", "equalizer", root.equalizerEnabled ? "off" : "on"])
              }
            }
            Caption { text: "Tab to move · arrows to adjust levels\nCtrl + F to search · Ctrl + 1 / 2 / 3 to switch views" }
          }
        }
        ScrollMark { view: root.currentView === 0 ? listenScroll : root.currentView === 1 ? mixerScroll : settingsScroll }
      }
    }
  }

  // A quiet, theme-coloured thumb that remains visible whenever content overflows.
  // It is outside the moving content so it also works in offscreen/native shells.
  component ScrollMark: Item {
    id: mark
    required property var view
    anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
    width: Style.space(8); z: 20
    visible: view.contentHeight > view.height + 1
    Rectangle {
      id: thumb
      anchors.right: parent.right
      width: Style.space(3)
      height: Math.max(Style.space(24), mark.height * Math.min(1, mark.view.height / Math.max(1, mark.view.contentHeight)))
      y: Math.max(0, Math.min(mark.height - height, mark.view.contentY / Math.max(1, mark.view.contentHeight - mark.view.height) * (mark.height - height)))
      radius: width / 2
      color: Qt.alpha(root.contentForeground, mouse.containsMouse || mouse.pressed ? 0.8 : 0.4)
    }
    MouseArea {
      id: mouse
      anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      function move(y) {
        var fraction = Math.max(0, Math.min(1, (y - thumb.height / 2) / Math.max(1, mark.height - thumb.height)))
        mark.view.contentY = fraction * Math.max(0, mark.view.contentHeight - mark.view.height)
      }
      onPressed: function(event) { move(event.y) }
      onPositionChanged: function(event) { if (pressed) move(event.y) }
    }
  }
  component PageTitle: Text {
    width: parent.width
    textFormat: Text.PlainText; color: root.contentForeground
    font.family: root.contentFontFamily; font.pixelSize: Style.font.title; font.bold: true
  }
  component SectionTitle: Text {
    width: parent.width
    textFormat: Text.PlainText; color: root.contentForeground
    font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
  }
  component Caption: Text {
    width: parent.width
    textFormat: Text.PlainText; color: root.contentMuted; wrapMode: Text.Wrap
    font.family: root.contentFontFamily; font.pixelSize: Style.font.caption
  }
  component SettingToggle: Row {
    id: setting
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled()
    width: parent.width; spacing: Style.space(12)
    opacity: setting.enabled ? 1 : 0.45
    Column {
      width: parent.width - toggleControl.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
      Text { width: parent.width; text: setting.label; textFormat: Text.PlainText; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.Wrap }
      Caption { text: setting.hint; visible: text.length > 0 }
    }
    ToggleSwitch {
      id: toggleControl
      checked: setting.checked; interactive: setting.enabled
      activeFocusOnTab: true
      hasCursor: activeFocus
      foreground: root.contentForeground
      anchors.verticalCenter: parent.verticalCenter
      Accessible.name: setting.label
      Keys.onSpacePressed: setting.toggled()
      Keys.onReturnPressed: setting.toggled()
      onToggled: setting.toggled()
    }
  }
  component SettingSlider: Row {
    id: sliderRow
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property string suffix: ""
    signal edited(int value)
    width: parent.width; spacing: Style.space(10)
    Text { width: Style.space(108); text: sliderRow.label; textFormat: Text.PlainText; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
    PanelSlider {
      width: parent.width - Style.space(108) - readout.width - parent.spacing * 2
      bar: root.bar; minimum: sliderRow.minimum; maximum: sliderRow.maximum; step: sliderRow.step; integer: true
      value: sliderRow.value
      trackColor: Qt.alpha(root.contentForeground, 0.16); fillColor: root.contentForeground; knobColor: root.contentForeground
      activeFocusOnTab: true
      Accessible.role: Accessible.Slider; Accessible.name: sliderRow.label
      Keys.onLeftPressed: sliderRow.edited(Math.max(sliderRow.minimum, sliderRow.value - sliderRow.step))
      Keys.onRightPressed: sliderRow.edited(Math.min(sliderRow.maximum, sliderRow.value + sliderRow.step))
      onReleased: function(value) { sliderRow.edited(value) }
      anchors.verticalCenter: parent.verticalCenter
    }
    Text { id: readout; width: Style.space(36); text: sliderRow.suffix; color: root.contentMuted; font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
  }
}
