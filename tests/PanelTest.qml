import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi

Window {
  id: window
  width: 500
  height: 700
  visible: false

  Lofi.Panel { id: panel }
  QtObject {
    id: voiceHost
    property string statusJson: ""
    property var lastArguments: []
    property var argumentsHistory: []
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(args) { lastArguments = args; argumentsHistory = argumentsHistory.concat([args]) }
  }

  TestCase {
    name: "FocusPanel"
    property string phase: ""
    when: true
    function init() { phase = ""; panel.editGuards = ({}) }
    function sourceCard(id) {
      function seek(parent) {
        if (parent.objectName === "sourceCard-" + id) return parent
        for (var child of parent.children || []) { var found = seek(child); if (found) return found }
        return null
      }
      return seek(findChild(panel,"section-body-nature"))
    }

    function test_instantRevealPersists() {
      panel.applyStatus(JSON.stringify({running: false, paused: false, reveal_speed: 0}))
      compare(panel.revealSpeed, 0)
      compare(panel.revealDuration, 0)
    }

    function test_liveAndFiniteProgress() {
      // A radio decoder's buffer duration is not a recording timeline.
      panel.applyStatus(JSON.stringify({running: true, paused: false, category: "lofi", can_seek: false, main_position: 30, main_duration: 120}))
      compare(panel.hasProgress, false)
      panel.applyStatus(JSON.stringify({running: true, paused: false, category: "youtube", can_seek: true, main_position: 30, main_duration: 120}))
      compare(panel.hasProgress, true)
      compare(panel.progressFraction, 0.25)
      panel.applyStatus(JSON.stringify({running: true, paused: false, category: "youtube", can_seek: false, main_position: 30, main_duration: 120}))
      compare(panel.hasProgress, false)
      panel.applyStatus(JSON.stringify({running: true, paused: false, category: "youtube", can_seek: true, main_position: null, main_duration: null}))
      compare(panel.hasProgress, false)
    }

    function test_animationPreference() {
      panel.applyStatus(JSON.stringify({running: true, paused: false, animations: false}))
      compare(panel.motionOn, false)
      compare(panel.steamOn, false)
      compare(panel.equalizerOn, false)
    }

    function test_libraryStatusAndSaveFeedback() {
      panel.applyStatus(JSON.stringify({running:false,paused:false,youtube_available:true,
        youtube_entries:[{id:"youtube-test",name:"Saved conversation",position:30}]}))
      compare(panel.youtubeEntries.length, 1)
      panel.youtubeUrl.text = "https://youtu.be/BaW_jenozKc"
      panel.youtubeTitle.text = "A conversation"
      panel.savingLink = true
      panel.youtubeResult(["youtube-add"], 1, "Invalid link")
      compare(panel.savingLink, false)
      compare(panel.libraryError, true)
      compare(panel.youtubeTitle.text, "A conversation")
      panel.youtubeResult(["youtube-add"], 0, "")
      compare(panel.youtubeUrl.text, "")
      compare(panel.libraryError, false)
    }

    function test_finishedVideoHasReplayState() {
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_state:"ended",category:"youtube"}))
      compare(panel.sourceEnded, true)
      compare(panel.isPlaying, false)
      compare(panel.heroStatus, "Finished")
    }

    function test_voiceLoadingFailureAndRetryAreVisibleWithoutMixingSourceErrors() {
      panel.showView(1)
      panel.hostWidget = voiceHost
      panel.applyStatus(JSON.stringify({running:true,paused:false,mix:true,
        bg_station:"voice-test",bg_state:"loading",main_state:"playing"}))
      compare(panel.voiceLoading, true)
      compare(panel.voiceMessage, "Loading podcast…")
      var status = findChild(panel, "voiceStatus")
      verify(status !== null)
      compare(status.text, "Loading podcast…")
      panel.applyStatus(JSON.stringify({running:true,paused:false,mix:true,
        bg_station:"voice-test",bg_state:"stopped",main_state:"playing",
        bg_error:"Podcast unavailable: connection\nfailed"}))
      compare(panel.voiceFailed, true)
      compare(status.text, "Podcast unavailable: connection failed")
      var retry = findChild(panel, "voiceRetry")
      verify(retry !== null)
      verify(retry.visible)
      retry.clicked()
      compare(voiceHost.lastArguments, ["bg", "voice-test"])
      panel.applyStatus(JSON.stringify({running:true,paused:false,mix:true,
        bg_station:"voice-test",bg_state:"stopped",main_state:"failed",
        error:"Soundtrack connection failed"}))
      compare(panel.voiceFailed, false)
      compare(status.text, "")
      panel.applyStatus(JSON.stringify({running:true,paused:false,mix:true,
        bg_station:"voice-test",bg_state:"playing",main_state:"playing",
        error:"Podcast unavailable: old failure"}))
      compare(panel.voiceFailed, false)
      panel.hostWidget = null
    }

    function test_radioTransportAllowsVoiceAndSavedYoutubeSuspendsIt() {
      panel.showView(1)
      var picker = findChild(panel, "voicePicker")
      var hint = findChild(panel, "voiceAvailabilityHint")
      var level = findChild(panel, "voiceLevelDisclosure")
      verify(picker !== null)
      verify(hint !== null)
      verify(level !== null)

      // Catalog radio presets can use a YouTube transport. Older backends
      // identify them by source_kind even though category is "youtube".
      panel.applyStatus(JSON.stringify({running:true,paused:false,category:"youtube",
        source_kind:"radio",mix:true,bg_state:"loading"}))
      compare(panel.voiceAvailable, true)
      compare(picker.enabled, true)
      compare(hint.visible, false)
      compare(level.expanded, true)
      compare(panel.voiceLoading, true)

      // New status communicates the policy directly, including failure UI.
      panel.applyStatus(JSON.stringify({running:true,paused:false,category:"youtube",
        source_kind:"live",voice_available:true,mix:true,bg_state:"stopped",
        bg_error:"Podcast unavailable: feed unavailable"}))
      compare(panel.voiceAvailable, true)
      compare(picker.enabled, true)
      compare(hint.visible, false)
      compare(level.expanded, true)
      compare(panel.voiceFailed, true)

      // Saved links keep their voice restriction; explicit policy wins over
      // a generic radio classification from the audio decoder.
      panel.applyStatus(JSON.stringify({running:true,paused:false,category:"lofi",
        source_kind:"radio",voice_available:false,mix:true,bg_state:"loading"}))
      compare(panel.voiceAvailable, false)
      compare(picker.enabled, false)
      compare(hint.visible, true)
      compare(level.expanded, false)
      compare(panel.voiceLoading, false)
      compare(panel.voiceFailed, false)
      compare(panel.voiceMessage, "")

      // Compatibility with statuses predating voice_available is retained.
      panel.applyStatus(JSON.stringify({running:true,paused:false,category:"youtube",
        source_kind:"recording",mix:true,bg_state:"stopped",bg_error:"Unavailable"}))
      compare(panel.voiceAvailable, false)
      compare(picker.enabled, false)
      compare(panel.voiceFailed, false)
    }

    function test_scenesRoomAndLivingMixPreservePausedPlaybackAndUserLevels() {
      panel.hostWidget = voiceHost
      panel.showView(1)
      panel.categories = [{id:"ambience",stations:[{id:"noise-rain",name:"Rain"}]}]
      panel.applyStatus(JSON.stringify({running:true,paused:true,spatial_available:true,
        scenes:[{id:"scene-calm",name:"Calm room"}],scene_id:"scene-calm",scene_dirty:true,
        room:{preset:"cafe",size:60,softness:45,reflections:35},
        wander:{enabled:true,amount:30},
        nature_layers:[{id:"noise-rain",enabled:true,volume:40,effective_volume:18,
          distance:75,pan:-35,width:85,softness:55,reflections:20,echo:0,outside:true,living:true}]}))
      phase = "status fields"
      compare(panel.spatialAvailable,true)
      compare(panel.sceneId,"scene-calm")
      compare(panel.sceneDirty,true)
      compare(panel.roomState.preset,"cafe")
      compare(panel.wanderEnabled,true)
      compare(panel.wanderAmount,30)
      compare(panel.natureLayer("noise-rain").volume,40)
      compare(panel.natureLayer("noise-rain").effective_volume,18)
      phase = "effective nature readout"
      var space = findChild(panel,"roomEditor")
      compare(space.positionText(panel.natureLayer("noise-rain")),"Outside · Far · Left")
      phase = "scene actions"
      var scenes = findChild(panel,"sceneControls")
      compare(scenes.currentScene.name,"Calm room")
      scenes.applyRequested("scene-calm")
      compare(voiceHost.lastArguments,["scene-apply","scene-calm"])
      scenes.saveRequested("Evening room")
      compare(voiceHost.lastArguments,["scene-save","Evening room"])
      scenes.confirmingRemoval = true
      findChild(scenes,"sceneRemoveConfirm").clicked()
      compare(voiceHost.lastArguments,["scene-remove","scene-calm"])
      phase = "living mix"
      findChild(panel,"livingMixToggle").toggled()
      compare(voiceHost.lastArguments,["wander","off"])
      compare(panel.wanderEnabled,false)
      findChild(panel,"livingMixAmount").edited(75)
      compare(voiceHost.lastArguments,["wander-amount","75"])
      phase = "room preset"
      findChild(panel,"roomPresetPicker").changed("hall")
      compare(voiceHost.lastArguments,["room","preset","hall"])
      compare(panel.playerPaused,true)
      compare(panel.natureLayer("noise-rain").volume,40)
      // Native policy is explicit; older statuses hide the new controls.
      panel.applyStatus(JSON.stringify({running:false,paused:false}))
      compare(panel.spatialAvailable,false)
      panel.hostWidget = null
    }

    function test_spatialEditorUsesLayerIdsAndKeepsSelectionOnStatusUpdates() {
      panel.hostWidget = voiceHost
      panel.showView(1)
      panel.categories = [{id:"ambience",stations:[{id:"noise-rain",name:"Rain"},{id:"noise-fireplace",name:"Fireplace"}]}]
      panel.applyStatus(JSON.stringify({running:true,paused:false,spatial_available:true,
        nature_layers:[{id:"noise-rain",enabled:true,volume:30,living:true},
          {id:"noise-fireplace",enabled:true,volume:20}]}))
      panel.spatialEditorOpen = true
      var editor = findChild(panel,"roomEditor")
      compare(editor.currentLayer.id,"noise-rain")
      findChild(editor,"spaceDistance").edited(90)
      compare(voiceHost.lastArguments,["layer","noise-rain","distance","90"])
      findChild(editor,"spacePan").edited(-30)
      compare(voiceHost.lastArguments,["layer","noise-rain","pan","-30"])
      findChild(editor,"spaceOutside").toggled()
      compare(voiceHost.lastArguments,["layer","noise-rain","outside","on"])
      findChild(editor,"spaceLiving").toggled()
      compare(voiceHost.lastArguments,["layer","noise-rain","living","off"])
      editor.roomEdited("size",90)
      compare(voiceHost.lastArguments,["room","size","90"])
      voiceHost.argumentsHistory = []
      editor.positionEdited("noise-fireplace",35,60)
      compare(voiceHost.argumentsHistory,[["layer","noise-fireplace","pan","35"],["layer","noise-fireplace","distance","60"]])
      compare(panel.selectedNatureId,"noise-fireplace")
      panel.applyStatus(JSON.stringify({running:true,paused:false,spatial_available:true,
        nature_layers:[{id:"noise-rain",enabled:true,volume:30},
          {id:"noise-fireplace",enabled:true,volume:20,pan:35,distance:60}]}))
      compare(editor.currentLayer.id,"noise-fireplace")
      compare(editor.currentLayer.pan,35)
      // Removing the selected source picks a remaining source safely.
      panel.applyStatus(JSON.stringify({running:true,paused:false,spatial_available:true,
        nature_layers:[{id:"noise-rain",enabled:true,volume:30}]}))
      compare(panel.selectedNatureId,"noise-rain")
      compare(editor.currentLayer.id,"noise-rain")
      panel.hostWidget = null
    }

    function test_importedSoundsExtendThePickerAndUsePrivateLibraryCommands() {
      panel.hostWidget = voiceHost
      panel.categories = [{id:"ambience",stations:[{id:"noise-rain",name:"Rain"}]}]
      panel.applyStatus(JSON.stringify({running:false,paused:false,spatial_available:true,
        imported_sounds:[{id:"imported-rain",name:"My rain"}],nature_layers:[]}))
      compare(panel.noiseOptions.length,2)
      compare(panel.noiseOptions[1].value,"imported-rain")
      compare(panel.noiseOptions[1].label,"My rain")
      var importer = findChild(panel,"soundImport")
      compare(importer.filePath("file:///tmp/My%20rain.ogg"),"/tmp/My rain.ogg")
      importer.expanded = true
      findChild(importer,"soundImportPath").text = "/tmp/My rain.ogg"
      findChild(importer,"soundImportTitle").text = "Rain on the porch"
      findChild(importer,"soundImportConfirm").clicked()
      compare(voiceHost.lastArguments,["sound-import","/tmp/My rain.ogg","Rain on the porch"])
      compare(importer.expanded,false)
      panel.pendingSoundRemoval = "imported-rain"
      findChild(panel,"soundRemoveConfirm").clicked()
      compare(voiceHost.lastArguments,["sound-remove","imported-rain"])
      compare(panel.pendingSoundRemoval,"")
      compare(panel.playerRunning,false)
      panel.hostWidget = null
    }

    function test_coverageCardsAndPresetsKeepVolumeAndSelection() {
      panel.hostWidget = voiceHost
      panel.showView(1)
      panel.natureCardExpanded = true
      panel.spatialEditorOpen = false
      panel.categories = [{id:"ambience",stations:[{id:"noise-rain",name:"Rain"},{id:"noise-fireplace",name:"Fireplace"}]}]
      panel.applyStatus(JSON.stringify({running:true,paused:true,spatial_available:true,
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,distance:78,pan:0,width:100,coverage:100},
          {id:"noise-fireplace",enabled:true,volume:50,distance:18,pan:-45,width:100,coverage:12}]}))
      tryVerify(function() { return sourceCard("noise-fireplace") !== null },1000)
      var fire = sourceCard("noise-fireplace")
      phase = "coverage selection"
      fire.selectedRequested()
      compare(panel.selectedNatureId,"noise-fireplace")
      compare(fire.expanded,true)
      compare(sourceCard("noise-rain").expanded,false)
      compare(findChild(fire,"sourceDetailsLoader").active,true)
      compare(findChild(sourceCard("noise-rain"),"sourceDetailsLoader").active,false)
      findChild(fire,"spaceCoverage").edited(65)
      phase = "coverage command"
      compare(voiceHost.lastArguments,["layer","noise-fireplace","coverage","65"])
      compare(panel.natureLayer("noise-fireplace").width,100)
      compare(panel.natureLayer("noise-fireplace").volume,50)
      findChild(fire,"sourcePreset-near").clicked()
      phase = "near preset"
      compare(panel.natureLayer("noise-fireplace").distance,18)
      compare(panel.natureLayer("noise-fireplace").coverage,12)
      findChild(fire,"sourcePreset-far").clicked()
      phase = "far preset"
      compare(panel.natureLayer("noise-fireplace").distance,80)
      compare(panel.natureLayer("noise-fireplace").coverage,25)
      voiceHost.argumentsHistory = []
      findChild(fire,"sourcePreset-around").clicked()
      phase = "around preset"
      compare(voiceHost.argumentsHistory,[["layer","noise-fireplace","coverage","100"],["layer","noise-fireplace","pan","0"]])
      compare(panel.natureLayer("noise-fireplace").volume,50)
      compare(panel.natureLayer("noise-fireplace").distance,80)
      compare(panel.playerPaused,true)
      phase = "coverage refreshed selection"
      panel.applyStatus(JSON.stringify({running:true,paused:true,spatial_available:true,
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,effective_volume:20,coverage:100},
          {id:"noise-fireplace",enabled:true,volume:50,effective_volume:30,distance:80,pan:0,coverage:100}]}))
      compare(panel.selectedNatureId,"noise-fireplace")
      compare(fire.expanded,true)
      panel.spatialEditorOpen = true
      phase = "coverage map hides cards"
      compare(findChild(panel,"section-body-nature").height,0)
      compare(findChild(fire,"sourceDetailsLoader").active,false)
      compare(findChild(panel,"roomEditor").currentLayer.id,"noise-fireplace")
      panel.hostWidget = null
    }

    function test_soloStaysAvailableWhileEditingAndDisabledWhenPaused() {
      panel.hostWidget = voiceHost
      panel.categories = [{id:"ambience",stations:[{id:"noise-rain",name:"Rain"}]}]
      panel.applyStatus(JSON.stringify({running:true,paused:true,spatial_available:true,scene_dirty:false,
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:100}]}))
      tryVerify(function() { return sourceCard("noise-rain") !== null },1000)
      var card = sourceCard("noise-rain")
      var audition = findChild(card,"sourceAudition")
      phase = "audition paused"
      compare(audition.enabled,false)
      voiceHost.argumentsHistory = []
      panel.auditionNature("noise-rain")
      phase = "audition paused command"
      compare(voiceHost.argumentsHistory,[])
      panel.applyStatus(JSON.stringify({running:true,paused:false,spatial_available:true,scene_dirty:false,
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:100}]}))
      compare(audition.enabled,true)
      phase = "audition start"
      audition.clicked()
      compare(voiceHost.lastArguments,["audition","noise-rain","hold"])
      compare(panel.sceneDirty,false)
      compare(panel.natureLayer("noise-rain").volume,35)
      phase = "audition active status"
      panel.applyStatus(JSON.stringify({running:true,paused:false,spatial_available:true,audition_id:"noise-rain",
        scene_dirty:false,nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:100}]}))
      compare(audition.text,"Back to mix")
      compare(findChild(panel,"soloBanner").visible,true)
      panel.selectedNatureId = ""
      compare(findChild(panel,"soloBanner").visible,true)
      phase = "audition end"
      findChild(panel,"soloReturnToMix").clicked()
      compare(voiceHost.lastArguments,["audition","noise-rain","off"])
      panel.applyStatus(JSON.stringify({running:false,paused:false,nature_layers:[]}))
      compare(panel.auditionId,"")
      panel.hostWidget = null
    }

    function test_identicalLibraryModelsKeepSourceCardsAndDetailsAlive() {
      panel.hostWidget = voiceHost
      panel.showView(1); panel.spatialEditorOpen = false; panel.natureCardExpanded = true
      panel.categories = [{id:"ambience",stations:[{id:"noise-rain",name:"Rain"}]}]
      var state = {running:true,paused:false,spatial_available:true,animations:false,
        imported_sounds:[{id:"imported-fire",name:"My fire"}],
        scenes:[{id:"scene-calm",name:"Calm"}],
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:50}]}
      panel.applyStatus(JSON.stringify(state))
      var card = sourceCard("noise-rain"), options = panel.noiseOptions
      var imports = panel.importedSounds, scenes = panel.scenes
      var detail = findChild(card,"sourceDetailsLoader").item
      var slider = findChild(findChild(card,"spaceCoverage"),"soundControlSlider")
      verify(slider !== null)
      for (var index = 0; index < 8; index++) {
        state.nature_layers[0].effective_volume = index
        state.nature_layers[0].volume = 36 + index
        panel.applyStatus(JSON.stringify(state))
        compare(panel.importedSounds,imports)
        compare(panel.scenes,scenes)
        compare(panel.noiseOptions,options)
        compare(sourceCard("noise-rain"),card)
        compare(findChild(card,"sourceDetailsLoader").item,detail)
        compare(findChild(findChild(card,"spaceCoverage"),"soundControlSlider"),slider)
      }
      panel.hostWidget = null
    }

    function test_latestEditSurvivesOlderStatusAfterItsAcknowledgement() {
      panel.hostWidget = voiceHost
      panel.setVolume("main",73)
      var state = {running:true,paused:false,main_volume:73,animations:false}
      panel.applyStatus(JSON.stringify(state))
      compare(panel.mainVolume,73)
      state.main_volume = 42
      panel.applyStatus(JSON.stringify(state))
      compare(panel.mainVolume,73)
      panel.runAction(["ui","fadeSeconds","6"])
      panel.runAction(["room","reflections","54"])
      state.fade_seconds = 2; state.room = {reflections:10}
      panel.applyStatus(JSON.stringify(state))
      compare(panel.fadeSeconds,6)
      compare(panel.roomState.reflections,54)
      // A scene is an intentional new value boundary.
      panel.runAction(["scene-apply","scene-new"])
      panel.applyStatus(JSON.stringify(state))
      compare(panel.mainVolume,42)
      compare(panel.fadeSeconds,2)
      compare(panel.roomState.reflections,10)
      panel.hostWidget = null
    }

    function test_pendingEditExpiresAndFailedEditReconcilesWhilePaused() {
      panel.hostWidget = voiceHost
      panel.applyStatus(JSON.stringify({running:true,paused:true,main_volume:42,animations:false}))
      panel.setVolume("main",73)
      panel.applyStatus(JSON.stringify({running:true,paused:true,main_volume:42,animations:false}))
      compare(panel.mainVolume,73)
      tryCompare(panel,"mainVolume",42,2000)
      compare(Object.keys(panel.editGuards).length,0)
      panel.setVolume("main",64)
      voiceHost.actionFinished(["vol","main","73"],1,"Older action failed")
      compare(panel.mainVolume,64)
      verify(panel.editGuards["vol:main"] !== undefined)
      voiceHost.actionFinished(["vol","main","64"],1,"Playback unavailable")
      compare(panel.mainVolume,42)
      compare(Object.keys(panel.editGuards).length,0)
      compare(panel.playerPaused,true)
      panel.hostWidget = null
    }

    function test_closedPanelStopsDecorativeMotion() {
      panel.close()
      panel.animationsEnabled = true
      compare(panel.liveMotion, false)
      var wave = Qt.createComponent("Plugin/PlaybackWave.qml").createObject(panel, {active:true,animate:false})
      verify(wave !== null)
      compare(wave.moving, false)
      wave.destroy()
    }

    function test_barWidgetCompiles() {
      var component = Qt.createComponent("Plugin/BarWidget.qml")
      compare(component.status, Component.Ready, component.errorString())
    }

    function cleanup() {
      if (qtest_results.failed) console.error("PANEL FAILURE", qtest_results.functionName, phase)
    }

    function cleanupTestCase() {
      console.log("PANEL_TEST_RESULT", JSON.stringify({
        passed: qtest_results.passCount,
        failed: qtest_results.failCount
      }))
    }
  }
}
