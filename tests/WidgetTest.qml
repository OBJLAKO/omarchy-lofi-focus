import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi
Window {
  id: window
  width: 100; height: 60; visible: false
  Lofi.BarWidget { id: widget; x: 20; y: 10 }
  SignalSpy { id: replies; target: widget; signalName: "actionFinished" }
  TestCase {
    name: "SkylofiNativeWidget"
    when: true
    function init() {
      tryCompare(widget, "statusReady", true, 5000)
      replies.clear()
    }
    function test_snapshotFromRealNativeProcess() {
      var state = JSON.parse(widget.statusJson)
      compare(state.native_backend, true)
      compare(typeof state.running, "boolean")
      compare(widget.pendingRequestCount, 0)
    }
    function test_masterWheelCoalescesAndReceivesReply() {
      widget.setMasterVolume(55)
      widget.setMasterVolume(70)
      widget.setMasterVolume(75)
      tryCompare(replies, "count", 1)
      compare(replies.signalArguments[0][0], ["vol", "master", "75"])
      compare(replies.signalArguments[0][1], 0)
      tryCompare(widget, "masterVolume", 75)
      compare(widget.pendingRequestCount, 0)
    }
    function test_actionFailureIsReportedAndUnblocksRequests() {
      widget.runAction(["unknown-test-command"])
      tryCompare(replies, "count", 1)
      compare(replies.signalArguments[0][1], 1)
      verify(replies.signalArguments[0][2].length > 0)
      compare(widget.pendingRequestCount, 0)
      widget.runAction(["ui", "fade", "off"])
      tryCompare(replies, "count", 2)
      compare(replies.signalArguments[1][1], 0)
      compare(widget.pendingRequestCount, 0)
    }
    function cleanup() {
      if (qtest_results.failed) console.error("WIDGET FAILURE", qtest_results.functionName)
    }
    function cleanupTestCase() {
      console.log("WIDGET_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
