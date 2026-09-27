import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi

Window {
  id: window
  width: 500
  height: 700
  visible: true
  Lofi.YoutubeLibrary {
    id: library
    x: 20; y: 20; width: 440
    entries: [{id:"youtube-test",name:"A saved conversation",position:90}]
  }
  SignalSpy { id: saves; target: library; signalName: "saveRequested" }
  SignalSpy { id: removals; target: library; signalName: "removeRequested" }
  TestCase {
    name: "YouTubeLibrary"
    when: window.visible
    function init() {
      library.addingLink = false
      library.pendingRemoval = ""
      library.urlField.text = ""
      library.titleField.text = ""
      saves.clear(); removals.clear()
    }
    function openForm() {
      mouseClick(findChild(library, "addYoutube"))
      tryCompare(library, "addingLink", true)
      tryCompare(library.urlField, "activeFocus", true)
    }
    function test_emptyLinkCannotBeSaved() {
      openForm()
      compare(findChild(library, "saveYoutube").enabled, false)
    }
    function test_pasteAndSave() {
      openForm()
      library.urlField.text = "https://youtu.be/BaW_jenozKc"
      library.titleField.text = "A long conversation"
      var button = findChild(library, "saveYoutube")
      tryCompare(button, "enabled", true)
      waitForPolish(window)
      waitForRendering(button)
      mouseClick(button, button.width / 2, button.height / 2)
      compare(saves.count, 1)
    }
    function test_enterSubmitsLink() {
      openForm()
      library.urlField.text = "https://youtu.be/BaW_jenozKc"
      keyClick(Qt.Key_Return)
      compare(saves.count, 1)
    }
    function test_removalNeedsExplicitSecondClick() {
      mouseClick(findChild(library, "removeYoutube-youtube-test"))
      compare(removals.count, 0)
      compare(library.pendingRemoval, "youtube-test")
      waitForPolish(window)
      mouseClick(findChild(library, "confirmRemoveYoutube-youtube-test"))
      compare(removals.count, 1)
      compare(removals.signalArguments[0][0], "youtube-test")
    }
    function cleanup() {
      if (qtest_results.failed) console.error("LIBRARY FAILURE", qtest_results.functionName)
    }
    function cleanupTestCase() {
      console.log("LIBRARY_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
