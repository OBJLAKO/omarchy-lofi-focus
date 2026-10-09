import QtQuick
import QtQuick.Window
import QtTest

Window {
  id: window
  width: 500
  height: 500
  visible: true

  Flickable {
    id: page
    x: 20; y: 20; width: 460; height: 460
    contentWidth: width
    contentHeight: 1000
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    SkylofiSlider {
      id: slider
      x: 60; y: 250; width: 300
      minimum: 0; maximum: 100; value: 50; step: 5
      animate: false
      // Keep the throttle pending until release, so the test can check its
      // final-value flush independently of the event loop's timing.
      updateInterval: 10000
    }
  }

  SignalSpy { id: edits; target: slider; signalName: "edited" }
  SignalSpy { id: releases; target: slider; signalName: "released" }
  SignalSpy { id: rightClicks; target: slider; signalName: "rightClicked" }

  TestCase {
    name: "SkylofiSliderInteraction"
    when: window.visible
    property string phase: ""

    function init() {
      page.cancelFlick()
      page.contentY = 150
      slider.value = 50
      slider.liveValue = 50
      slider.lastEditedValue = 50
      slider.localValueHeld = false
      slider.focus = false
      window.contentItem.forceActiveFocus()
      edits.clear()
      releases.clear()
      rightClicks.clear()
      phase = ""
      waitForPolish(window)
    }

    function test_dragOutsideBoundsKeepsGrabAndFlushesOnRelease() {
      var originalScroll = page.contentY
      phase = "press"
      mousePress(slider, slider.width / 2, slider.height / 2)
      verify(slider.dragging)
      // Keep left pressed while leaving both the slider and its thumb. The
      // diagonal motion crosses Flickable's drag threshold in both axes.
      mouseMove(slider, slider.width * 0.7, -30, 20, Qt.LeftButton)
      mouseMove(slider, slider.width * 0.85, -60, 20, Qt.LeftButton)
      phase = "outside drag: dragging=" + slider.dragging + ", value=" + slider.liveValue + ", scroll=" + page.contentY
      verify(slider.dragging, "The scrolling page stole the slider's active drag")
      verify(slider.liveValue > 80, "Volume stopped following the pointer outside the slider")
      compare(page.contentY, originalScroll, "Dragging volume must not scroll the page")
      compare(edits.count, 0)
      phase = "release"
      mouseRelease(slider, slider.width * 0.85, -60)
      compare(slider.dragging, false)
      compare(edits.count, 1, "Release must immediately flush the last pending volume")
      compare(releases.count, 1)
      fuzzyCompare(edits.signalArguments[0][0], slider.liveValue, 0.0001)
      fuzzyCompare(releases.signalArguments[0][0], slider.liveValue, 0.0001)
    }

    function test_dragClampsAtEndpointsAndReturnsInside() {
      phase = "outside endpoints"
      mousePress(slider, slider.width / 2, slider.height / 2)
      mouseMove(slider, slider.width + 30, -30, 20, Qt.LeftButton)
      mouseMove(slider, slider.width + 60, -60, 20, Qt.LeftButton)
      verify(slider.dragging)
      compare(slider.liveValue, slider.maximum)
      mouseMove(slider, -30, slider.height + 40, 20, Qt.LeftButton)
      verify(slider.dragging)
      compare(slider.liveValue, slider.minimum)
      phase = "return inside"
      var track = findChild(slider, "sliderTrack")
      mouseMove(slider, track.x + track.width / 4, slider.height / 2, 20, Qt.LeftButton)
      verify(slider.dragging)
      fuzzyCompare(slider.liveValue, 25, 0.2)
      mouseRelease(slider, track.x + track.width / 4, slider.height / 2)
      compare(slider.dragging, false)
      compare(edits.count, 1)
      compare(releases.count, 1)
    }

    function test_dragOutsideSliderStillScrollsPage() {
      phase = "page scrolling"
      var originalScroll = page.contentY
      mousePress(page, 20, 200)
      mouseMove(page, 20, 170, 20, Qt.LeftButton)
      mouseMove(page, 20, 130, 20, Qt.LeftButton)
      mouseMove(page, 20, 100, 20, Qt.LeftButton)
      verify(page.contentY > originalScroll)
      compare(slider.dragging, false)
      compare(slider.liveValue, 50)
      compare(edits.count, 0)
      mouseRelease(page, 20, 100)
    }

    function test_keyboardAndFocusedWheelKeepEditing() {
      phase = "keyboard"
      slider.forceActiveFocus()
      keyClick(Qt.Key_Right)
      compare(slider.liveValue, 55)
      keyClick(Qt.Key_Left)
      compare(slider.liveValue, 50)
      keyClick(Qt.Key_Home)
      compare(slider.liveValue, slider.minimum)
      keyClick(Qt.Key_End)
      compare(slider.liveValue, slider.maximum)
      phase = "focused wheel"
      mouseWheel(slider, slider.width / 2, slider.height / 2, 0, -120)
      compare(slider.liveValue, 95)
      compare(edits.count, 5)
      compare(releases.count, 1)
    }

    function test_unfocusedWheelPassesThroughAndRightClickStaysSecondary() {
      phase = "unfocused wheel: activeFocus=" + slider.activeFocus
      verify(!slider.activeFocus)
      var originalScroll = page.contentY
      mouseWheel(slider, slider.width / 2, slider.height / 2, 0, -120)
      phase = "unfocused wheel: value=" + slider.liveValue + ", edits=" + edits.count
      compare(slider.liveValue, 50)
      compare(edits.count, 0)
      tryVerify(function() { return page.contentY > originalScroll })
      page.cancelFlick()
      page.contentY = originalScroll
      phase = "right click"
      mouseClick(slider, slider.width / 2, slider.height / 2, Qt.RightButton)
      compare(rightClicks.count, 1)
      compare(slider.dragging, false)
      compare(slider.liveValue, 50)
      compare(edits.count, 0)
      compare(releases.count, 0)
    }

    function cleanup() {
      if (qtest_results.failed)
        console.error("SLIDER_INTERACTION_ASSERT", qtest_results.functionName, phase)
      // Also release after a failed assertion, so the next case is isolated.
      mouseRelease(window.contentItem, 250, 250)
      page.cancelFlick()
    }

    function cleanupTestCase() {
      console.log("SLIDER_INTERACTION_RESULT", JSON.stringify({
        passed: qtest_results.passCount,
        failed: qtest_results.failCount
      }))
    }
  }
}
