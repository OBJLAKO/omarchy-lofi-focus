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
    function test_disconnectedEditsCoalesceByParameterAndKeepFifoBarriers() {
      widget.statusReady = false
      widget.actionQueue = []
      var first = [["vol","main","10"],["layer","noise-rain","coverage","20"],
        ["room","size","30"],["ui","fadeSeconds","2"],["wander-amount","10"]]
      for (var args of first) widget.runAction(args)
      for (var value = 1; value <= 100; value++) widget.runAction(["layer","noise-rain","coverage",String(value)])
      compare(widget.actionQueue.length,5)
      compare(widget.actionQueue[4],["layer","noise-rain","coverage","100"])
      widget.runAction(["scene-save","Before changes"])
      widget.runAction(["vol","main","75"])
      widget.runAction(["vol","main","80"])
      compare(widget.actionQueue.length,7)
      compare(widget.actionQueue[0],["vol","main","10"])
      compare(widget.actionQueue[5],["scene-save","Before changes"])
      compare(widget.actionQueue[6],["vol","main","80"])
      widget.runAction(["scene-apply","scene-calm"])
      widget.runAction(["layer","noise-rain","coverage","35"])
      widget.runAction(["nature-remove","noise-rain"])
      widget.runAction(["layer","noise-rain","coverage","40"])
      compare(widget.actionQueue.slice(7),[["scene-apply","scene-calm"],
        ["layer","noise-rain","coverage","35"],["nature-remove","noise-rain"],
        ["layer","noise-rain","coverage","40"]])
      widget.actionQueue = []
      for (var index = 0; index < 32; index++) widget.runAction(["layer","noise-test-"+index,"coverage","30"])
      compare(widget.actionQueue.length,32)
      widget.runAction(["layer","noise-test-0","coverage","90"])
      compare(widget.actionQueue.length,32)
      compare(widget.actionQueue[31],["layer","noise-test-0","coverage","90"])
      widget.runAction(["room","size","60"])
      compare(widget.actionQueue.length,32)
      compare(replies.count,1)
      compare(replies.signalArguments[0][1],1)
      widget.actionQueue = []; widget.statusReady = true
    }
    function cleanup() {
      if (qtest_results.failed) console.error("WIDGET FAILURE", qtest_results.functionName)
    }
    function cleanupTestCase() {
      console.log("WIDGET_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
