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
  property bool standaloneUltraMode: false
  readonly property bool ultraMode: hostWidget && "ultraMode" in hostWidget
    ? hostWidget.ultraMode : standaloneUltraMode
  readonly property var barIdentity: hostWidget || root

  // Normal panels share the bar's watcher. Standalone previews/popouts use
  // this fallback without changing the saved animation preferences.
  FileView {
    path: root.hostWidget ? "" : Quickshell.env("HOME") + "/.local/state/sky-power-profile/appearance-active"
    watchChanges: !root.hostWidget
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.standaloneUltraMode = text().trim() !== "" && text().trim() === Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    onLoadFailed: root.standaloneUltraMode = false
  }

  // ---- Player state, mirrored from status.json
  property bool playerRunning: false
  property bool musicRunning: false
  property bool voiceRunning: false
  property bool voiceAvailable: true
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
  property bool spatialAvailable: false
  property var importedSounds: []
  property bool managingImports: false
  property string pendingSoundRemoval: ""
  property var scenes: []
  property string sceneId: ""
  property bool sceneDirty: false
  property var roomState: ({preset:"cozy",size:35,softness:55,reflections:25})
  onRoomStateChanged: if (roomPresetPicker) roomPresetPicker.value = roomState.preset
  property bool wanderEnabled: false
  property int wanderAmount: 20
  property bool spatialEditorOpen: false
  property bool spatialScrollRequested: false
  property Item mixerFocusItem: null
  property string selectedNatureId: ""
  property bool natureCardExpanded: true
  property bool roomDetailsOpen: false
  property string auditionId: ""
  readonly property var activeNatureLayers: natureLayers.filter(function(layer) { return layer.enabled === true })
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
  property bool canSeek: false
  property string sourceKind: "unknown"

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

  readonly property bool motionOn: animationsEnabled && !ultraMode
  readonly property bool liveMotion: motionOn && opened
  readonly property bool steamOn: false
  readonly property bool glowOn: false
  readonly property bool equalizerOn: motionOn && equalizerEnabled
  // Reveal is a touch slower than a snap but never sluggish; the speed slider
  // scales the base timings.
  readonly property real revealStep: 45 * revealSpeed
  readonly property int revealDuration: Math.round(160 * revealSpeed)

  readonly property bool isPlaying: playerRunning && !playerPaused && !sourceEnded
  readonly property bool audiblePlayback: playerRunning && !playerPaused && masterVolume > 0 && (
    (musicRunning && mainState === "playing" && mainVolume > 0)
    || (voiceRunning && bgState === "playing" && bgVolume > 0)
    || natureLayers.some(function(layer) { return layer.running === true && Number(layer.volume) > 0 })
  )
  readonly property bool musicConnecting: mainState === "connecting" || mainState === "reconnecting"
  readonly property bool sessionActive: playerRunning || musicConnecting
  readonly property bool voiceLoading: mixOn && voiceAvailable && bgState === "loading"
  readonly property bool voiceFailed: mixOn && voiceAvailable && !voiceLoading && bgState !== "playing" && bgError.length > 0
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
  readonly property string sourceLabel: root.playerRunning && !root.musicRunning && !root.musicConnecting && root.enabledNatureCount > 0
    ? "Nature mix" : root.canSeek ? "Recording" : root.sourceKind === "radio" ? "Live radio" : root.sourceKind === "recording" ? "Recording"
      : root.sourceKind === "live" ? "YouTube live" : "Online audio"

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
        id: st.id, name: st.name,
        description: String(st.description || "").replace(/\s*·\s*requires yt-dlp/ig, "").replace(/\s*·\s*formerly Chillofi/ig, ""),
        glyph: categoryGlyph(c.id)
      })
    }
    return out
  }

  function isMusicPlaying(id) {
    return root.sessionActive && !root.playerPaused && root.playerStationId === id && root.musicRunning
  }

  // Some live services report a moving duration. A timeline is only useful
  // when the backend has positively identified a finite recording.
  readonly property bool hasProgress: root.canSeek && root.mainDuration > 0 && root.mainPosition >= 0
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
    for (var imported of root.importedSounds) {
      if (!out.some(function(sound) { return sound.value === imported.id }))
        out.push({value:imported.id,label:imported.name,description:"Imported sound"})
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
      root.voiceRunning = state.bg_running === undefined ? root.bgState === "playing" : state.bg_running === true
      var backgroundError = typeof state.bg_error === "string" ? state.bg_error
        : typeof state.error === "string" && state.error.indexOf("Podcast unavailable:") === 0 ? state.error : ""
      root.bgError = backgroundError.replace(/[\r\n\t]+/g, " ").slice(0, 300)
      root.mixOn = state.mix === true
      root.natureLayers = Array.isArray(state.nature_layers) ? state.nature_layers : []
      root.spatialAvailable = state.spatial_available === true
      root.auditionId = typeof state.audition_id === "string" ? state.audition_id : ""
      root.importedSounds = Array.isArray(state.imported_sounds) ? state.imported_sounds.filter(function(sound) {
        return sound && typeof sound.id === "string" && typeof sound.name === "string"
      }).slice(0, 64) : []
      if (root.pendingSoundRemoval && !root.importedSounds.some(function(sound) { return sound.id === root.pendingSoundRemoval }))
        root.pendingSoundRemoval = ""
      root.scenes = Array.isArray(state.scenes) ? state.scenes.filter(function(scene) {
        return scene && typeof scene.id === "string" && typeof scene.name === "string"
      }).slice(0, 32) : []
      root.sceneId = String(state.scene_id || "")
      root.sceneDirty = state.scene_dirty === true
      var room = state.room && typeof state.room === "object" ? state.room : {}
      root.roomState = {
        preset:["cozy","cafe","outside","hall"].indexOf(room.preset) >= 0 ? room.preset : "cozy",
        size:clampVolume(room.size,35),softness:clampVolume(room.softness,55),reflections:clampVolume(room.reflections,25)
      }
      var wander = state.wander && typeof state.wander === "object" ? state.wander : {}
      root.wanderEnabled = wander.enabled === true
      root.wanderAmount = clampVolume(wander.amount,20)
      if (!root.activeNatureLayers.some(function(layer) { return layer.id === root.selectedNatureId }))
        root.selectedNatureId = root.activeNatureLayers.length ? root.activeNatureLayers[0].id : ""
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
      root.canSeek = state.can_seek === true
      root.sourceKind = ["radio", "recording", "live", "unknown"].indexOf(state.source_kind) >= 0
        ? state.source_kind : root.canSeek ? "recording" : root.playerCategory === "lofi" ? "radio" : "unknown"
      root.voiceAvailable = typeof state.voice_available === "boolean" ? state.voice_available
        : root.sourceKind === "radio" || !root.youtubeSelected
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
  function editRoom(key, value) {
    var next = Object.assign({}, root.roomState)
    next[key] = key === "preset" ? value : clampVolume(value, 0)
    root.roomState = next
    root.sceneDirty = true
    root.runAction(["room", key, String(next[key])])
  }
  function editLayer(id, key, value) {
    var updated = root.natureLayers.slice()
    var booleanKey = key === "outside" || key === "living"
    var normalized = booleanKey ? value === "on"
      : key === "pan" ? Math.max(-100, Math.min(100, Math.round(Number(value) || 0))) : clampVolume(value, 0)
    for (var i = 0; i < updated.length; i++) {
      if (updated[i].id === id) {
        var next = Object.assign({}, updated[i]); next[key] = normalized; updated[i] = next
      }
    }
    root.natureLayers = updated
    root.sceneDirty = true
    root.runAction(["layer", id, key, booleanKey ? normalized ? "on" : "off" : String(normalized)])
  }
  function placeLayer(id, pan, distance) {
    // One local update keeps the selected source stable while dragging. The
    // transport receives two bounded commands only when the gesture ends.
    var updated = root.natureLayers.map(function(layer) {
      return layer.id === id ? Object.assign({}, layer, {pan:pan,distance:distance}) : layer
    })
    root.natureLayers = updated; root.selectedNatureId = id; root.sceneDirty = true
    root.runAction(["layer", id, "pan", String(pan)])
    root.runAction(["layer", id, "distance", String(distance)])
  }
  function selectNatureCard(id) {
    root.natureCardExpanded = root.selectedNatureId === id && !root.spatialEditorOpen ? !root.natureCardExpanded : true
    root.selectedNatureId = id
    root.spatialEditorOpen = false
  }
  function sourcePreset(id, preset) {
    // Placement presets never replace the user's volume or saved soundtrack.
    if (preset === "around") {
      root.editLayer(id,"coverage",100)
      root.editLayer(id,"pan",0)
    } else if (preset === "near" || preset === "far") {
      root.editLayer(id,"distance",preset === "near" ? 18 : 80)
      root.editLayer(id,"coverage",preset === "near" ? 12 : 25)
    }
  }
  function auditionNature(id) {
    if (!root.isPlaying) return
    root.runAction(["audition",id,root.auditionId === id ? "off" : "on"])
  }
  function setWanderAmount(value) {
    root.wanderAmount = clampVolume(value,20); root.sceneDirty = true
    root.runAction(["wander-amount", String(root.wanderAmount)])
  }
  function natureLayer(id) {
    for (var layer of natureLayers) if (layer.id === id) return layer
    return { enabled: false, running: false, volume: 25 }
  }
  function isCollapsed(key) { return root.collapsibleSections && root.collapsed[key] === true }
  function ensureVisible(scroll, item) {
    if (scroll === mixerScroll) root.mixerFocusItem = item
    var point = item.mapToItem(scroll.contentItem, 0, 0)
    var target = scroll.contentY
    if (item.height > scroll.height) target = point.y
    else if (point.y < target) target = point.y
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
    if (!opened) { voicePicker.close(); naturePicker.close(); sceneControls.close(); roomEditor.close() }
    else {
      if (hostWidget && hostWidget.statusJson) root.applyStatus(hostWidget.statusJson)
      Qt.callLater(root.animatePage)
    }
  }
  function animatePage() {
    if (root.liveMotion) pageReveal.restart()
    else { pageReveal.stop(); pages.opacity = 1 }
  }
  onLiveMotionChanged: if (!root.liveMotion) { pageReveal.stop(); pages.opacity = 1 }
  onCurrentViewChanged: {
    voicePicker.close(); naturePicker.close(); sceneControls.close(); roomEditor.close()
    Qt.callLater(root.animatePage)
  }
  onLibraryOpenChanged: Qt.callLater(root.animatePage)
  NumberAnimation {
    id: pageReveal
    objectName: "pageTransition"
    target: pages; property: "opacity"; from: 0.72; to: 1
    duration: visual.transitionDuration; easing.type: Easing.OutCubic
  }

  SkylofiStyle {
    id: visual
    foreground: root.contentForeground
    background: Color.popups.background
    accent: Color.accent
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    padding: visual.padding
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(visual.panelWidth)
    // The host fitter adds content padding; the cap keeps the whole card at
    // the design height while still shrinking to the available screen space.
    contentHeight: panel.fittedContentHeight(visual.panelHeight, visual.panelHeight)

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (sceneControls.saving || sceneControls.confirmingRemoval) sceneControls.close()
          else if (voicePicker.popupOpen) voicePicker.close()
          else if (naturePicker.popupOpen) naturePicker.close()
          else if (youtubeLibrary.addingLink) youtubeLibrary.addingLink = false
          else if (youtubeLibrary.pendingRemoval.length > 0) youtubeLibrary.pendingRemoval = ""
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
        spacing: Style.space(12)
        Row {
          width: parent.width
          height: Style.space(32)
          spacing: visual.controlGap
          Text {
            width: parent.width - closeButton.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: "Skylofi"
            textFormat: Text.PlainText
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: visual.title
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          SkylofiButton {
            fontFamily: root.contentFontFamily
            animate: root.liveMotion
            id: closeButton
            iconText: "\uf00d"
            tooltipText: "Close · Esc"
            foreground: visual.muted
            width: Style.space(32); height: Style.space(32)
            horizontalPadding: 0; verticalPadding: 0
            focusable: true
            Accessible.name: "Close panel"
            onClicked: root.close()
          }
        }
        Row {
          id: tabs
          objectName: "mainNavigation"
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: ["Listen", "Mix", "Settings"]
            NavTab {
              required property string modelData
              required property int index
              objectName: "mainTab-" + index
              width: (tabs.width - tabs.spacing * 2) / 3
              text: modelData
              selected: root.currentView === index
              onActivated: root.showView(index)
            }
          }
        }
      }

      Item {
        id: pages
        objectName: "pageViewport"
        anchors.top: chrome.bottom
        anchors.topMargin: visual.groupGap
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: playerDock.top
        anchors.bottomMargin: visual.groupGap
        clip: true
        Flickable {
          id: listenScroll
          objectName: "listenScroll"
          anchors.fill: parent
          contentWidth: width; contentHeight: contentColumn.implicitHeight
          clip: true; visible: root.currentView === 0
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          Column {
            id: contentColumn
            objectName: "focusContent"
            width: parent.width - (listenScroll.contentHeight > listenScroll.height ? Style.space(10) : 0)
            spacing: Style.space(12)
            Row {
              width: parent.width
              spacing: Style.space(8)
              SourceTab {
                objectName: "radioSourceTab"
                width: Style.space(110)
                text: "Radio"
                selected: !root.libraryOpen
                onActivated: root.libraryOpen = false
              }
              SourceTab {
                objectName: "savedSourceTab"
                width: Math.min(Style.space(170), parent.width - Style.space(118))
                text: "Saved links" + (root.youtubeEntries.length > 0 ? " · " + root.youtubeEntries.length : "")
                selected: root.libraryOpen
                onActivated: root.libraryOpen = true
              }
            }
            TextField {
              id: stationSearch
              objectName: "stationSearch"
              width: parent.width
              height: visual.controlHeight
              visible: !root.libraryOpen
              placeholderText: "Search radio"
              foreground: root.contentForeground
              font.family: root.contentFontFamily; font.pixelSize: visual.body
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
                  animate: root.liveMotion
                  foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  onActivated: root.runAction(["start", modelData.id])
                  onActiveFocusChanged: if (activeFocus) root.ensureVisible(listenScroll, this)
                }
              }
              Caption {
                visible: stationSearch.text.length > 0 && root.musicStations.filter(function(st) { return (st.name + " " + st.description).toLowerCase().indexOf(stationSearch.text.trim().toLowerCase()) >= 0 }).length === 0
                text: "No matching stations. Try another search."
              }
            }
            YoutubeLibrary {
              id: youtubeLibrary
              objectName: "youtubeLibrary"
              visible: root.libraryOpen
              width: parent.width
              entries: root.youtubeEntries; selectedId: root.playerStationId
              playing: root.isPlaying && root.youtubeSelected
              animate: root.liveMotion
              foreground: root.contentForeground; muted: visual.muted; fontFamily: root.contentFontFamily
              available: root.youtubeAvailable; saving: root.savingLink
              message: root.libraryMessage; failed: root.libraryError
              onSaveRequested: root.saveYoutube()
              onPlayRequested: function(id) { root.runAction(["start", id]) }
              onRemoveRequested: function(id) { root.runAction(["youtube-remove", id]) }
              onFocusRequested: function(item) { root.ensureVisible(listenScroll, item) }
            }
          }
        }

        Flickable {
          id: mixerScroll
          objectName: "mixScroll"
          anchors.fill: parent
          contentWidth: width; contentHeight: mixColumn.implicitHeight
          visible: root.currentView === 1; clip: true
          onContentHeightChanged: Qt.callLater(function() {
            if (root.spatialScrollRequested && spaceDisclosure.height >= roomEditor.stageItem.height) {
              root.ensureVisible(mixerScroll,roomEditor.stageItem)
              root.spatialScrollRequested = false
            } else if (root.mixerFocusItem && root.mixerFocusItem.visible) {
              // Loader activation and wrapped text settle during polish. Keep
              // the requested hit target visible after that final layout.
              root.ensureVisible(mixerScroll,root.mixerFocusItem)
            }
          })
          boundsBehavior: Flickable.StopAtBounds; interactive: contentHeight > height
          Column {
            id: mixColumn
            width: parent.width - (mixerScroll.contentHeight > mixerScroll.height ? Style.space(10) : 0)
            spacing: visual.groupGap
            SceneControls {
              id: sceneControls
              objectName: "sceneControls"
              width: parent.width
              visible: root.spatialAvailable
              scenes: root.scenes; sceneId: root.sceneId; dirty: root.sceneDirty
              foreground: root.contentForeground; fontFamily: root.contentFontFamily
              animate: root.liveMotion; popupBoundary: keyCatcher
              onApplyRequested: function(id) { root.runAction(["scene-apply",id]) }
              onSaveRequested: function(name) { root.runAction(["scene-save",name]) }
              onRemoveRequested: function(id) { root.runAction(["scene-remove",id]) }
              onFocusRequested: function(item) { root.ensureVisible(mixerScroll,item) }
            }
            ControlGroup {
              objectName: "roomControls"
              width: parent.width
              visible: root.spatialAvailable
              Row {
                width: parent.width; spacing: Style.space(8)
                SectionTitle {
                  width: Style.space(46); text: "Room"
                  anchors.verticalCenter: parent.verticalCenter
                }
                FocusDropdown {
                  id: roomPresetPicker
                  objectName: "roomPresetPicker"
                  width: parent.width - Style.space(54)
                  showLabel: false; label: "Room acoustics"; placeholderText: "Find a room"
                  options: [{value:"cozy",label:"Warm room"},{value:"cafe",label:"Cafe"},{value:"outside",label:"Outdoors"},{value:"hall",label:"Large hall"}]
                  value: root.roomState.preset
                  popupBoundary: keyCatcher; animate: root.liveMotion
                  foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  onChanged: function(value) { root.editRoom("preset",value) }
                  onActiveFocusChanged: if (activeFocus) root.ensureVisible(mixerScroll,this)
                }
              }
              SkylofiButton {
                objectName: "roomDetailsButton"
                width: parent.width
                text: root.roomDetailsOpen ? "Hide room acoustics" : "Room acoustics"
                iconText: root.roomDetailsOpen ? "\uf107" : "\uf105"
                leftAlign: true; horizontalPadding: 0; verticalPadding: 0
                foreground: visual.muted; fontFamily: root.contentFontFamily; fontSize: visual.caption
                animate: root.liveMotion; focusable: true
                onClicked: root.roomDetailsOpen = !root.roomDetailsOpen
                onActiveFocusChanged: if (activeFocus) root.ensureVisible(mixerScroll,this)
              }
              Column {
                width: parent.width; visible: root.roomDetailsOpen; spacing: Style.space(10)
                Repeater {
                  model: [{key:"size",label:"Room size",fallback:35},{key:"softness",label:"Soft furnishings",fallback:55},{key:"reflections",label:"Room reflections",fallback:25}]
                  SoundControl {
                    required property var modelData
                    objectName: "room-" + modelData.key
                    label: modelData.label; value: root.roomState[modelData.key]
                    bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                    animate: root.liveMotion
                    onEdited: function(value) { root.editRoom(modelData.key,value) }
                    onFocusRequested: function(item) { root.ensureVisible(mixerScroll,item) }
                  }
                }
              }
            }
            ControlGroup {
              width: parent.width
              Row {
                width: parent.width
                spacing: visual.controlGap
                SectionTitle {
                  width: parent.width - (naturePicker.visible ? naturePicker.width + parent.spacing : 0)
                  text: "Ambience"
                  anchors.verticalCenter: parent.verticalCenter
                }
                FocusDropdown {
                  id: naturePicker
                  objectName: "naturePicker"
                  popupBoundary: keyCatcher
                  width: Math.min(Style.space(136), parent.width * 0.46)
                  visible: root.availableSounds.length > 0
                  label: "Add ambience sound"
                  showLabel: false; triggerLabel: width < Style.space(120) ? "+ Add" : "+ Add sound"
                  showDescriptions: false; animate: root.liveMotion
                  placeholderText: "Find a sound"
                  options: root.availableSounds; value: ""
                  foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  onChanged: function(value) {
                    root.selectedNatureId = value
                    root.runAction(["nature", value, "on"])
                    Qt.callLater(function() { naturePicker.value = "" })
                  }
                  onActiveFocusChanged: if (activeFocus) root.ensureVisible(mixerScroll, this)
                }
              }
              Caption { visible: root.enabledNatureCount === 0; text: "Add rain, a room tone or your own audio." }
              SkylofiButton {
                objectName: "soundSpaceButton"
                width: parent.width
                visible: root.spatialAvailable && root.enabledNatureCount > 0
                text: root.spatialEditorOpen ? "Back to sound cards" : "Edit overall space"
                iconText: root.spatialEditorOpen ? "\uf107" : "\uf105"
                leftAlign: true; horizontalPadding: Style.space(2)
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                animate: root.liveMotion; focusable: true
                onClicked: {
                  root.spatialScrollRequested = !root.spatialEditorOpen
                  root.spatialEditorOpen = !root.spatialEditorOpen
                }
              }
              Item {
                id: natureBody
                objectName: "section-body-nature"
                width: parent.width
                visible: !root.spatialAvailable || !root.spatialEditorOpen
                height: root.spatialAvailable && root.spatialEditorOpen || root.isCollapsed("nature") ? 0 : natureColumn.implicitHeight
                clip: true
                Column {
                  id: natureColumn
                  width: parent.width; spacing: Style.space(8)
                  move: Transition {
                    NumberAnimation { properties: "y"; duration: root.liveMotion && natureColumn.visible ? visual.disclosureDuration : 0; easing.type: Easing.OutCubic }
                  }
                  Repeater {
                    model: root.noiseOptions
                    Column {
                      required property var modelData
                      readonly property var soundState: root.natureLayer(modelData.value)
                      visible: soundState.enabled
                      width: parent.width; spacing: Style.space(2)
                      SourceCard {
                        objectName: "sourceCard-" + modelData.value
                        width: parent.width; visible: root.spatialAvailable
                        sound: soundState; label: modelData.label
                        selected: root.selectedNatureId === modelData.value
                        expanded: selected && root.natureCardExpanded && !root.spatialEditorOpen
                        canAudition: root.isPlaying; auditioning: root.auditionId === modelData.value
                        bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                        animate: root.liveMotion
                        onSelectedRequested: root.selectNatureCard(modelData.value)
                        onRemoveRequested: root.runAction(["nature",modelData.value,"off"])
                        onVolumeEdited: function(value) { root.setVolume(modelData.value,value) }
                        onLayerEdited: function(key,value) { root.editLayer(modelData.value,key,value) }
                        onPresetRequested: function(preset) { root.sourcePreset(modelData.value,preset) }
                        onAuditionRequested: root.auditionNature(modelData.value)
                        onFocusRequested: function(item) { root.ensureVisible(mixerScroll,item) }
                      }
                      MixerLevel {
                        objectName: "natureLevel-" + modelData.value
                        width: parent.width; visible: !root.spatialAvailable
                        compact: true; labelWidth: Style.space(112)
                        label: modelData.label; value: soundState.volume; removable: true
                        bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                        animate: root.liveMotion
                        onEdited: function(value) { root.setVolume(modelData.value,value) }
                        onRemoveRequested: root.runAction(["nature",modelData.value,"off"])
                        onFocusRequested: function(item) { root.selectedNatureId = modelData.value; root.ensureVisible(mixerScroll,item) }
                      }
                    }
                  }
                }
              }
              Disclosure {
                id: spaceDisclosure
                width: parent.width
                expanded: root.spatialAvailable && root.spatialEditorOpen && root.enabledNatureCount > 0
                RoomEditor {
                  id: roomEditor
                  objectName: "roomEditor"
                  width: parent.width
                  layers: root.activeNatureLayers; options: root.noiseOptions
                  selectedId: root.selectedNatureId; room: root.roomState
                  canAudition: root.isPlaying; auditionId: root.auditionId
                  popupBoundary: keyCatcher; bar: root.bar
                  foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  animate: root.liveMotion
                  onSelected: function(id) { root.selectedNatureId = id }
                  onLayerEdited: function(id,key,value) { root.editLayer(id,key,value) }
                  onVolumeEdited: function(id,value) { root.setVolume(id,value) }
                  onPresetRequested: function(id,preset) { root.sourcePreset(id,preset) }
                  onAuditionRequested: function(id) { root.auditionNature(id) }
                  onPositionEdited: function(id,pan,distance) { root.placeLayer(id,pan,distance) }
                  onRoomEdited: function(key,value) { root.editRoom(key,value) }
                  onFocusRequested: function(item) { root.ensureVisible(mixerScroll,item) }
                }
              }
              SoundImport {
                objectName: "soundImport"
                width: parent.width; visible: root.spatialAvailable
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                animate: root.liveMotion
                onImportRequested: function(path,title) { root.runAction(["sound-import",path,title]) }
                onFocusRequested: function(item) { root.ensureVisible(mixerScroll,item) }
              }
              SkylofiButton {
                visible: root.spatialAvailable && root.importedSounds.length > 0
                text: root.managingImports ? "Hide imported library" : "Manage imported sounds"
                fontSize: visual.caption; foreground: visual.muted; fontFamily: root.contentFontFamily
                animate: root.liveMotion; focusable: true
                onClicked: { root.managingImports = !root.managingImports; root.pendingSoundRemoval = "" }
              }
              Column {
                width: parent.width; spacing: Style.space(6)
                visible: root.spatialAvailable && root.managingImports && root.importedSounds.length > 0
                Repeater {
                  model: root.importedSounds
                  Row {
                    required property var modelData
                    width: parent.width; spacing: Style.space(8)
                    Caption {
                      width: parent.width - removeImport.width - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                    }
                    SkylofiButton {
                      id: removeImport
                      objectName: "removeImport-" + modelData.id
                      text: "Remove"; foreground: visual.muted; fontFamily: root.contentFontFamily
                      fontSize: visual.caption; animate: root.liveMotion; focusable: true
                      onClicked: root.pendingSoundRemoval = modelData.id
                    }
                  }
                }
                Caption {
                  visible: root.pendingSoundRemoval.length > 0
                  text: {
                    var sound = root.importedSounds.find(function(sound) { return sound.id === root.pendingSoundRemoval })
                    return "Remove " + (sound ? sound.name : "this sound") + " from your library?"
                  }
                }
                Row {
                  width: parent.width; spacing: Style.space(6)
                  visible: root.pendingSoundRemoval.length > 0
                  SkylofiButton {
                    objectName: "soundRemoveConfirm"
                    text: "Remove"; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                    animate: root.liveMotion; focusable: true; bordered: true
                    onClicked: { root.runAction(["sound-remove",root.pendingSoundRemoval]); root.pendingSoundRemoval = "" }
                  }
                  SkylofiButton {
                    text: "Keep"; foreground: visual.muted; fontFamily: root.contentFontFamily
                    animate: root.liveMotion; focusable: true
                    onClicked: root.pendingSoundRemoval = ""
                  }
                }
              }
            }
            ControlGroup {
              width: parent.width
              visible: root.spatialAvailable
              Row {
                width: parent.width; spacing: Style.space(8)
                Text {
                  width: parent.width - livingMixToggle.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Living mix"; textFormat: Text.PlainText
                  color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: visual.body
                }
                SkylofiSwitch {
                  id: livingMixToggle
                  objectName: "livingMixToggle"
                  checked: root.wanderEnabled; animate: root.liveMotion
                  foreground: root.contentForeground; Accessible.name: "Living mix"
                  Accessible.description: "Slow, gentle ambience variation without changing your faders"
                  onToggled: { root.wanderEnabled = !root.wanderEnabled; root.sceneDirty = true; root.runAction(["wander",root.wanderEnabled ? "on" : "off"]) }
                  onActiveFocusChanged: if (activeFocus) root.ensureVisible(mixerScroll,this)
                }
              }
              Disclosure {
                width: parent.width; expanded: root.wanderEnabled
                Row {
                  id: variationRow
                  objectName: "livingMixAmount"
                  signal edited(int value)
                  width: parent.width; spacing: Style.space(8)
                  onEdited: function(value) { root.setWanderAmount(value) }
                  Text {
                    id: variationLabel
                    width: Style.space(68); anchors.verticalCenter: parent.verticalCenter
                    text: "Variation"; color: visual.muted
                    font.family: root.contentFontFamily; font.pixelSize: visual.label
                  }
                  SkylofiSlider {
                    width: parent.width - variationLabel.width - variationReadout.width - parent.spacing * 2
                    height: Style.space(32); minimum: 0; maximum: 100; step: 5; integer: true
                    value: root.wanderAmount; animate: root.liveMotion; bar: root.bar
                    trackColor: visual.sliderTrack; fillColor: Color.accent; knobColor: Color.accent
                    activeFocusOnTab: true; Accessible.role: Accessible.Slider
                    Accessible.name: "Living mix variation"
                    Accessible.description: root.wanderAmount + " percent"
                    Keys.onLeftPressed: variationRow.edited(Math.max(0,root.wanderAmount - 5))
                    Keys.onRightPressed: variationRow.edited(Math.min(100,root.wanderAmount + 5))
                    onReleased: function(value) { variationRow.edited(value) }
                    onActiveFocusChanged: if (activeFocus) root.ensureVisible(mixerScroll,this)
                  }
                  Text {
                    id: variationReadout
                    width: Style.space(34); anchors.verticalCenter: parent.verticalCenter
                    text: root.wanderAmount + "%"; horizontalAlignment: Text.AlignRight
                    color: visual.muted; font.family: root.contentFontFamily; font.pixelSize: visual.caption
                  }
                }
              }
            }
            MixerLevel {
              objectName: "soundtrackLevel"
              width: parent.width
              compact: true; labelWidth: Style.space(90)
              label: "Soundtrack"; value: root.mainVolume
              bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
              animate: root.liveMotion
              onEdited: function(value) { root.setVolume("main", value) }
              onFocusRequested: function(item) { root.ensureVisible(mixerScroll, item) }
            }
            ControlGroup {
              width: parent.width
              SectionTitle { text: "Voice" }
              FocusDropdown {
                id: voicePicker
                objectName: "voicePicker"
                popupBoundary: keyCatcher
                width: parent.width
                label: "Background voice"
                showLabel: false; options: root.backgroundOptions
                animate: root.liveMotion
                value: root.mixOn ? root.bgStation : "off"
                enabled: root.voiceAvailable
                opacity: enabled ? 1 : 0.45
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                placeholderText: "Search voices and podcasts"
                onChanged: function(value) { root.runAction(["bg", value]) }
                onActiveFocusChanged: if (activeFocus) root.ensureVisible(mixerScroll, this)
              }
              Caption {
                objectName: "voiceAvailabilityHint"
                visible: !root.voiceAvailable
                text: "Voice is available with radio. Switch to Radio in Listen to use it."
              }
              Row {
                width: parent.width
                visible: root.voiceMessage.length > 0
                spacing: visual.controlGap
                Caption {
                  objectName: "voiceStatus"
                  width: parent.width - (voiceRetry.visible ? voiceRetry.width + parent.spacing : 0)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.voiceMessage
                  color: root.voiceFailed ? Color.urgent : visual.muted
                }
                SkylofiButton {
                  fontFamily: root.contentFontFamily
                  animate: root.liveMotion
                  id: voiceRetry
                  objectName: "voiceRetry"
                  visible: root.voiceFailed && root.bgStation.length > 0
                  text: "Retry"; foreground: root.contentForeground; focusable: true
                  onClicked: root.runAction(["bg", root.bgStation])
                }
              }
              Disclosure {
                width: parent.width
                objectName: "voiceLevelDisclosure"
                expanded: root.mixOn && root.voiceAvailable
                MixerLevel {
                  width: parent.width
                  compact: true; labelWidth: Style.space(90)
                  label: "Voice level"; value: root.bgVolume
                  bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
                  animate: root.liveMotion
                  onEdited: function(value) { root.setVolume("bg", value) }
                  onFocusRequested: function(item) { root.ensureVisible(mixerScroll, item) }
                }
              }
            }
          }
        }

        Flickable {
          id: settingsScroll
          objectName: "settingsScroll"
          anchors.fill: parent
          contentWidth: width; contentHeight: settingsColumn.implicitHeight
          visible: root.currentView === 2; clip: true
          boundsBehavior: Flickable.StopAtBounds; interactive: contentHeight > height
          Column {
            id: settingsColumn
            width: parent.width - (settingsScroll.contentHeight > settingsScroll.height ? Style.space(10) : 0)
            spacing: visual.groupGap
            ControlGroup {
              width: parent.width
              SectionTitle { text: "Playback" }
              SettingToggle {
                objectName: "fadeToggle"
                label: "Fade in and out"
                hint: "Start and pause sounds gently."
                checked: root.fadeEnabled
                onToggled: root.runAction(["ui", "fade", root.fadeEnabled ? "off" : "on"])
              }
              Disclosure {
                width: parent.width
                expanded: root.fadeEnabled
                SettingSlider {
                objectName: "fadeDuration"
                label: "Fade duration"; value: root.fadeSeconds
                minimum: 1; maximum: 8; step: 1; suffix: root.fadeSeconds + " s"
                onEdited: function(value) { root.runAction(["ui", "fadeSeconds", String(value)]) }
                }
              }
              Rectangle { width: parent.width; height: 1; color: visual.line }
              SettingToggle {
                objectName: "dictationToggle"
                label: "Lower audio while dictating"
                hint: "Automatically quiet sounds when VoxType records."
                checked: root.ducking
                onToggled: root.runAction(["ducking", root.ducking ? "off" : "on"])
              }
              Disclosure {
                width: parent.width
                expanded: root.ducking
                SettingSlider {
                objectName: "dictationVolume"
                label: "Volume while dictating"; value: root.duckLevel
                minimum: 0; maximum: 100; step: 5; suffix: root.duckLevel + "%"
                onEdited: function(value) { root.runAction(["ui", "duckLevel", String(value)]) }
                }
              }
            }
            ControlGroup {
              width: parent.width
              SectionTitle { text: "Interface" }
              SettingToggle {
                objectName: "animationsToggle"
                label: "Interface motion"
                hint: "Feedback and transitions between controls."
                checked: root.animationsEnabled
                onToggled: root.runAction(["ui", "animations", root.animationsEnabled ? "off" : "on"])
              }
              SettingToggle {
                objectName: "playbackIndicatorToggle"
                label: "Playback indicator"
                hint: root.animationsEnabled ? "A quiet moving mark while sounds play." : "Enable interface motion to animate the mark."
                enabled: root.animationsEnabled
                checked: root.equalizerEnabled
                onToggled: root.runAction(["ui", "equalizer", root.equalizerEnabled ? "off" : "on"])
              }
            }
          }
        }
        ScrollMark { view: root.currentView === 0 ? listenScroll : root.currentView === 1 ? mixerScroll : settingsScroll }
      }

      Column {
        id: playerDock
        objectName: "playbackDock"
        readonly property bool compactControls: width < Style.space(360)
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        spacing: Style.space(10)
        Rectangle { width: parent.width; height: 1; color: visual.line }
        Row {
          width: parent.width
          spacing: Style.space(10)
          Column {
            width: Math.max(0, parent.width - playButton.width - stopButton.width - parent.spacing * 2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              objectName: "nowPlayingName"
              width: parent.width
              text: root.playerRunning && !root.musicRunning && !root.musicConnecting && root.enabledNatureCount > 0
                ? "Nature mix" : root.playerName || "Choose a station"
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily; font.pixelSize: visual.body
              font.weight: Font.DemiBold; elide: Text.ElideRight
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              PlaybackWave {
                width: Style.space(12); height: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                active: root.audiblePlayback
                animate: root.liveMotion && root.equalizerEnabled
                ink: Color.accent
              }
              Text {
                width: parent.width - Style.space(18)
                text: root.sessionActive ? root.sourceLabel + " · " + root.heroStatus : root.heroStatus
                textFormat: Text.PlainText
                color: root.mainState === "failed" ? Color.urgent : visual.muted
                font.family: root.contentFontFamily; font.pixelSize: visual.caption
                elide: Text.ElideRight
              }
            }
          }
          SkylofiButton {
            fontFamily: root.contentFontFamily
            animate: root.liveMotion
            id: playButton
            objectName: "togglePlayback"
            readonly property string actionLabel: root.sourceEnded ? "Replay" : root.playerPaused ? "Resume" : root.sessionActive ? "Pause" : "Play"
            text: playerDock.compactControls ? "" : actionLabel
            tooltipText: actionLabel
            iconText: root.sessionActive && !root.playerPaused && !root.sourceEnded ? "\uf04c" : "\uf04b"
            selected: true
            width: playerDock.compactControls ? visual.controlHeight : Style.space(98); height: visual.controlHeight
            fontSize: visual.body; iconSize: visual.body
            foreground: root.contentForeground; focusable: true
            Accessible.name: actionLabel + " sounds"
            onClicked: root.runAction(["toggle"])
          }
          SkylofiButton {
            fontFamily: root.contentFontFamily
            animate: root.liveMotion
            id: stopButton
            objectName: "stopPlayback"
            text: playerDock.compactControls ? "Stop" : "Stop all"
            tooltipText: "Stop all sounds"
            width: playerDock.compactControls ? Style.space(58) : Style.space(72); height: visual.controlHeight
            fontSize: visual.label
            enabled: root.sessionActive
            opacity: enabled ? 1 : 0.4
            foreground: visual.muted; focusable: true
            Accessible.name: "Stop all sounds"
            onClicked: root.runAction(["stop"])
          }
        }
        Column {
          objectName: "finitePlaybackControls"
          visible: root.hasProgress
          width: parent.width
          spacing: Style.space(6)
          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              width: parent.width - times.width - parent.spacing
              text: root.mainTitle && root.mainTitle !== root.playerName ? root.mainTitle : "Recording"
              textFormat: Text.PlainText; color: visual.muted
              font.family: root.contentFontFamily; font.pixelSize: visual.caption
              elide: Text.ElideRight
            }
            Text {
              id: times
              text: root.formatTime(root.mainPosition) + " / " + root.formatTime(root.mainDuration)
              color: visual.muted
              font.family: root.contentFontFamily; font.pixelSize: visual.caption
            }
          }
          SkylofiSlider {
            objectName: "playbackProgress"
            animate: root.liveMotion
            width: parent.width; height: Style.space(24)
            minimum: 0; maximum: Math.max(1, root.mainDuration); step: 15
            value: Math.max(0, root.mainPosition)
            trackColor: visual.line
            fillColor: Color.accent; knobColor: Color.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Slider; Accessible.name: "Recording position"
            Keys.onLeftPressed: if (root.hasProgress) root.runAction(["seek", String(Math.max(0, root.mainPosition - 15))])
            Keys.onRightPressed: if (root.hasProgress) root.runAction(["seek", String(Math.min(root.mainDuration, root.mainPosition + 15))])
            onReleased: function(value) { if (root.hasProgress) root.runAction(["seek", String(value)]) }
          }
        }
        Row {
          visible: root.mainState === "failed"
          width: parent.width
          spacing: visual.controlGap
          Caption {
            width: parent.width - retryButton.width - parent.spacing
            text: "Source unavailable. Try again or choose another."
            anchors.verticalCenter: parent.verticalCenter
          }
          SkylofiButton {
            fontFamily: root.contentFontFamily
            animate: root.liveMotion
            id: retryButton
            text: "Retry"; foreground: root.contentForeground; focusable: true
            onClicked: root.runAction(["start", root.playerStationId])
          }
        }
        Caption { visible: text.length > 0; text: root.actionMessage; color: Color.urgent }
        MixerLevel {
          objectName: "allSoundsLevel"
          width: parent.width
          compact: true
          label: "All sounds"; value: root.masterVolume
          bar: root.bar; foreground: root.contentForeground; fontFamily: root.contentFontFamily
          animate: root.liveMotion
          onEdited: function(value) { root.setVolume("master", value) }
        }
      }
    }
  }

  component NavTab: Item {
    id: tab
    property string text: ""
    property bool selected: false
    signal activated()
    height: visual.controlHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.selected: selected
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()
    Rectangle {
      anchors.fill: parent
      color: tabMouse.pressed ? visual.pressed : tab.activeFocus || tabMouse.containsMouse ? visual.hover : "transparent"
      radius: Math.min(Style.cornerRadius, Style.space(6))
      border.color: tab.activeFocus ? Color.accent : "transparent"
      border.width: 1
      Behavior on color { enabled: root.liveMotion && tab.visible; ColorAnimation { duration: visual.feedbackDuration } }
    }
    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(12)
      text: tab.text; textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: tab.selected ? root.contentForeground : visual.muted
      font.family: root.contentFontFamily; font.pixelSize: tab.width < Style.space(125) ? visual.label : visual.body
      font.weight: tab.selected ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
    Rectangle {
      anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(12); anchors.rightMargin: Style.space(12)
      height: Style.space(2)
      color: tab.selected ? Color.accent : visual.line
      Behavior on color { enabled: root.liveMotion && tab.visible; ColorAnimation { duration: visual.feedbackDuration } }
    }
    MouseArea {
      id: tabMouse
      anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { tab.forceActiveFocus(); tab.activated() }
    }
  }
  component SourceTab: Item {
    id: sourceTab
    property string text: ""
    property bool selected: false
    signal activated()
    height: Style.space(30)
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.selected: selected
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()
    Rectangle {
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, Style.space(6))
      color: sourceMouse.pressed ? visual.pressed : sourceTab.selected ? visual.selected : sourceMouse.containsMouse || sourceTab.activeFocus ? visual.hover : "transparent"
      border.color: sourceTab.activeFocus ? Color.accent : "transparent"
      border.width: 1
      Behavior on color { enabled: root.liveMotion && sourceTab.visible; ColorAnimation { duration: visual.feedbackDuration } }
    }
    Text {
      anchors.centerIn: parent
      text: sourceTab.text; textFormat: Text.PlainText
      width: parent.width - Style.space(12)
      horizontalAlignment: Text.AlignHCenter
      color: sourceTab.selected ? root.contentForeground : visual.muted
      font.family: root.contentFontFamily; font.pixelSize: visual.label
      font.weight: sourceTab.selected ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
    MouseArea {
      id: sourceMouse
      anchors.fill: parent; hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { sourceTab.forceActiveFocus(); sourceTab.activated() }
    }
  }
  component ControlGroup: BorderSurface {
    id: group
    default property alias controls: groupColumn.data
    implicitHeight: groupColumn.implicitHeight + Style.space(28)
    radius: Math.min(Style.cornerRadius, Style.space(10))
    color: visual.surface
    borderSpec: Border.flat(visual.line, 1)
    Column {
      id: groupColumn
      anchors.left: parent.left; anchors.right: parent.right
      anchors.top: parent.top; anchors.margins: Style.space(14)
      spacing: Style.space(12)
    }
  }
  component Disclosure: Item {
    id: disclosure
    default property alias controls: disclosureBody.data
    property bool expanded: false
    readonly property bool animate: root.liveMotion && visible
    height: expanded ? disclosureBody.implicitHeight : 0
    visible: expanded || height > 0
    enabled: expanded
    clip: true
    onAnimateChanged: if (!animate) disclosureFeedback.complete()
    Behavior on height {
      enabled: disclosure.animate
      NumberAnimation { id: disclosureFeedback; duration: visual.disclosureDuration; easing.type: Easing.OutCubic }
    }
    Column { id: disclosureBody; width: parent.width }
  }
  component SectionTitle: Text {
    width: parent.width
    textFormat: Text.PlainText; color: root.contentForeground
    font.family: root.contentFontFamily; font.pixelSize: visual.label; font.weight: Font.DemiBold
    elide: Text.ElideRight
  }
  component Caption: Text {
    width: parent.width
    textFormat: Text.PlainText; color: visual.muted; wrapMode: Text.Wrap
    font.family: root.contentFontFamily; font.pixelSize: visual.caption
  }
  component SettingToggle: Row {
    id: setting
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled()
    width: parent.width; spacing: Style.space(12)
    Item {
      id: settingCopy
      width: parent.width - toggleControl.width - parent.spacing
      implicitHeight: settingLabels.implicitHeight
      anchors.verticalCenter: parent.verticalCenter
      Column {
        id: settingLabels
        width: parent.width
        spacing: Style.space(4)
        Text {
          width: parent.width; text: setting.label; textFormat: Text.PlainText
          color: root.contentForeground
          font.family: root.contentFontFamily; font.pixelSize: visual.body
          wrapMode: Text.Wrap
        }
        Caption { text: setting.hint; visible: text.length > 0 }
      }
      MouseArea {
        anchors.fill: parent
        enabled: setting.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: { toggleControl.forceActiveFocus(Qt.MouseFocusReason); setting.toggled() }
      }
    }
    SkylofiSwitch {
      id: toggleControl
      objectName: "settingSwitch"
      checked: setting.checked; interactive: setting.enabled
      animate: root.liveMotion
      hasCursor: activeFocus
      foreground: root.contentForeground
      anchors.verticalCenter: parent.verticalCenter
      Accessible.name: setting.label
      onToggled: setting.toggled()
      onActiveFocusChanged: if (activeFocus) root.ensureVisible(settingsScroll, setting)
    }
  }
  component SettingSlider: Column {
    id: sliderRow
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property string suffix: ""
    property var scrollView: settingsScroll
    signal edited(int value)
    width: parent.width; spacing: Style.space(6)
    Row {
      width: parent.width
      spacing: Style.space(10)
      Text {
        width: parent.width - readout.width - parent.spacing
        text: sliderRow.label; textFormat: Text.PlainText
        color: visual.muted
        font.family: root.contentFontFamily; font.pixelSize: visual.label
        elide: Text.ElideRight
      }
      Text {
        id: readout
        width: Style.space(48); text: sliderRow.suffix
        color: root.contentForeground
        font.family: root.contentFontFamily; font.pixelSize: visual.label
        horizontalAlignment: Text.AlignRight
      }
    }
    SkylofiSlider {
      width: parent.width; height: Style.space(30)
      animate: root.liveMotion
      bar: root.bar; minimum: sliderRow.minimum; maximum: sliderRow.maximum; step: sliderRow.step; integer: true
      value: sliderRow.value
      trackColor: visual.line; fillColor: Color.accent; knobColor: Color.accent
      activeFocusOnTab: true
      Accessible.role: Accessible.Slider; Accessible.name: sliderRow.label
      Keys.onLeftPressed: sliderRow.edited(Math.max(sliderRow.minimum, sliderRow.value - sliderRow.step))
      Keys.onRightPressed: sliderRow.edited(Math.min(sliderRow.maximum, sliderRow.value + sliderRow.step))
      onReleased: function(value) { sliderRow.edited(value) }
      onActiveFocusChanged: if (activeFocus) root.ensureVisible(sliderRow.scrollView, sliderRow)
    }
  }
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
      color: mouse.containsMouse || mouse.pressed ? visual.muted : visual.quiet
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
}
