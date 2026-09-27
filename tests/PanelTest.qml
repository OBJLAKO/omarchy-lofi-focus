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

  TestCase {
    name: "FocusPanel"
    when: true

    function test_instantRevealPersists() {
      panel.applyStatus(JSON.stringify({running: false, paused: false, reveal_speed: 0}))
      compare(panel.revealSpeed, 0)
      compare(panel.revealDuration, 0)
    }

    function test_liveAndFiniteProgress() {
      panel.applyStatus(JSON.stringify({running: true, paused: false, main_position: 30, main_duration: 120}))
      compare(panel.hasProgress, true)
      compare(panel.progressFraction, 0.25)
      panel.applyStatus(JSON.stringify({running: true, paused: false, main_position: null, main_duration: null}))
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
