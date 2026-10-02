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
    property string phase: ""
    when: window.visible
    function init() {
      library.entries = [{id:"youtube-test",name:"A saved conversation",position:90}]
      library.addingLink = false
      library.saving = false
      library.searching = false
      findChild(library, "librarySearch").text = ""
      library.pendingRemoval = ""
      library.urlField.text = ""
      library.titleField.text = ""
      saves.clear(); removals.clear()
      phase = "init"
    }
    function openForm() {
      waitForPolish(window)
      phase = "open click"
      mouseClick(findChild(library, "addYoutube"))
      phase = "open flag"
      tryCompare(library, "addingLink", true)
      phase = "open focus"
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
      phase = "save enabled"
      tryCompare(button, "enabled", true)
      phase = "save polished"
      waitForPolish(window)
      phase = "save rendered"
      waitForRendering(button)
      phase = "save click"
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
    function test_largeLibrarySearchFiltersEntries() {
      library.entries = [{id:"one",name:"Quiet jazz"},{id:"two",name:"A conversation"},{id:"three",name:"Rainy beats"},{id:"four",name:"Sunday"},{id:"five",name:"Piano"}]
      var search = findChild(library, "librarySearch")
      tryCompare(search, "visible", true)
      search.text = "jazz"
      tryCompare(findChild(library, "libraryEntry-one"), "visible", true)
      tryCompare(findChild(library, "libraryEntry-two"), "visible", false)
    }
    function test_searchShortcutCanShowSearchForSmallLibrary() {
      library.focusSearch()
      var search = findChild(library, "librarySearch")
      tryCompare(search, "visible", true)
      tryCompare(search, "activeFocus", true)
    }
    function test_enterWhileSavingDoesNotResubmit() {
      openForm()
      library.urlField.text = "https://youtu.be/BaW_jenozKc"
      library.saving = true
      keyClick(Qt.Key_Return)
      compare(saves.count, 0)
    }
    function cleanup() {
      if (qtest_results.failed) console.error("LIBRARY FAILURE", qtest_results.functionName, phase)
    }
    function cleanupTestCase() {
      console.log("LIBRARY_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
