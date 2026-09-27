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

    function cleanupTestCase() {
      console.log("PANEL_TEST_RESULT", JSON.stringify({
        passed: qtest_results.passCount,
        failed: qtest_results.failCount
      }))
    }
  }
}
