import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi

Window {
  id: window
  width: 160; height: 100; visible: true
  Item {
    id: holder
    anchors.fill: parent
    Lofi.PlaybackWave {
      id: wave
      x: 20; y: 20; width: 30; height: 24
      ink: "#88aacc"
    }
  }
  TestCase {
    name: "SkylofiPlaybackMotion"
    when: true
    function init() {
      window.visible = true
      holder.visible = true
      wave.visible = true
      wave.animate = true
      wave.active = false
      wave.phase = 0
      wave.frameCount = 0
      waitForPolish(window)
    }
    function test_ongoingPlaybackHasBoundedUpdates() {
      compare(wave.updateInterval, 125)
      wave.active = true
      tryCompare(wave, "moving", true)
      var started = Date.now()
      wait(1150)
      var elapsed = Date.now() - started
      verify(wave.moving, "Playback indication must continue after its initial response")
      verify(wave.frameCount >= 4, "Ongoing indication did not update")
      verify(wave.frameCount <= Math.ceil(elapsed / 125) + 1, "Playback indication exceeded its 8 Hz budget")
      verify(wave.phase !== 0 || wave.frameCount >= 12)
      for (var i = 0; i < 3; i++) verify(wave.stemScale(i) > 0.2 && wave.stemScale(i) < 0.9)
    }
    function test_pauseStopsImmediatelyAndResumes() {
      wave.active = true
      tryVerify(function() { return wave.frameCount > 0 })
      wave.active = false
      compare(wave.moving, false)
      compare(wave.phase, 0)
      for (var i = 0; i < 3; i++) compare(wave.stemScale(i), 0.25)
      var count = wave.frameCount
      wait(300)
      compare(wave.frameCount, count)
      wave.active = true
      tryCompare(wave, "moving", true)
      tryVerify(function() { return wave.frameCount > count })
    }
    function test_reducedMotionRemainsStaticAndClear() {
      wave.active = true
      wave.animate = false
      compare(wave.moving, false)
      compare(wave.stemScale(0), 0.55)
      compare(wave.stemScale(1), 0.68)
      compare(wave.stemScale(2), 0.42)
      var count = wave.frameCount
      wait(300)
      compare(wave.frameCount, count)
      wave.animate = true
      tryCompare(wave, "moving", true)
      tryVerify(function() { return wave.frameCount > count })
    }
    function test_hiddenItemStopsAndReopens() {
      wave.active = true
      tryVerify(function() { return wave.frameCount > 0 })
      wave.visible = false
      compare(wave.moving, false)
      var count = wave.frameCount
      wait(300)
      compare(wave.frameCount, count)
      wave.visible = true
      tryCompare(wave, "moving", true)
      tryVerify(function() { return wave.frameCount > count })
    }
    function test_hiddenParentStopsAndReopens() {
      wave.active = true
      tryVerify(function() { return wave.frameCount > 0 })
      holder.visible = false
      compare(wave.presented, false)
      compare(wave.moving, false)
      var count = wave.frameCount
      wait(300)
      compare(wave.frameCount, count)
      holder.visible = true
      tryCompare(wave, "moving", true)
      tryVerify(function() { return wave.frameCount > count })
    }
    function test_hiddenWindowStopsAndReopens() {
      wave.active = true
      tryVerify(function() { return wave.frameCount > 0 })
      window.visible = false
      compare(wave.presented, false)
      compare(wave.moving, false)
      var count = wave.frameCount
      wait(300)
      compare(wave.frameCount, count)
      window.visible = true
      tryCompare(wave, "moving", true)
      tryVerify(function() { return wave.frameCount > count })
    }
    function cleanup() {
      wave.active = false
      window.visible = true
    }
    function cleanupTestCase() {
      console.log("PLAYBACK_MOTION_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
