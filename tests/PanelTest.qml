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
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(args) { lastArguments = args }
  }

  TestCase {
    name: "FocusPanel"
    when: true

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
      if (qtest_results.failed) console.error("PANEL FAILURE", qtest_results.functionName)
    }

    function cleanupTestCase() {
      console.log("PANEL_TEST_RESULT", JSON.stringify({
        passed: qtest_results.passCount,
        failed: qtest_results.failCount
      }))
    }
  }
}
