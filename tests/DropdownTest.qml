import QtQuick
import QtQuick.Window
import QtTest

Window {
  id: window
  width: 500
  height: 500
  visible: true

  FocusDropdown {
    id: dropdown
    x: 20
    y: 20
    width: 250
    showLabel: false
    options: [
      { value: "rain", label: "Rain" },
      { value: "wind", label: "Wind" },
      { value: "thunder", label: "Thunderstorm" }
    ]
  }

  SignalSpy { id: selections; target: dropdown; signalName: "changed" }

  TestCase {
    name: "FocusDropdown"
    property string phase: ""
    // Quickshell hosts the real Omarchy theme types; unlike qmltestrunner,
    // it doesn't set QTestRootObject.windowShown.
    when: window.visible

    function init() {
      dropdown.close()
      tryCompare(findChild(dropdown, "focusDropdownPopup"), "visible", false)
      dropdown.value = ""
      selections.clear()
    }

    function openPicker() {
      mouseClick(dropdown, 80, 10)
      tryCompare(dropdown, "popupOpen", true)
    }

    function test_repeatClickCloses() {
      openPicker()
      mouseClick(dropdown, 80, 10)
      tryCompare(dropdown, "popupOpen", false)
      // A third click must still open it normally.
      openPicker()
      compare(selections.count, 0)
    }

    function test_outsideClickCloses() {
      openPicker()
      mouseClick(window.contentItem, 450, 450)
      tryCompare(dropdown, "popupOpen", false)
      compare(selections.count, 0)
    }

    function test_escapeCloses() {
      openPicker()
      keyClick(Qt.Key_Escape)
      tryCompare(dropdown, "popupOpen", false)
      compare(selections.count, 0)
    }

    function test_filterAndKeyboardSelection() {
      openPicker()
      var search = findChild(dropdown, "focusDropdownSearch")
      verify(search !== null)
      tryCompare(search, "activeFocus", true)
      keyClick(Qt.Key_W)
      keyClick(Qt.Key_I)
      keyClick(Qt.Key_N)
      tryCompare(dropdown, "filtered", [dropdown.options[1]])
      keyClick(Qt.Key_Return)
      tryCompare(dropdown, "popupOpen", false)
      compare(dropdown.value, "wind")
      compare(selections.count, 1)
      openPicker()
      compare(search.text, "")
      compare(dropdown.filtered.length, 3)
    }

    function test_mouseSelection() {
      openPicker()
      phase = "find results"
      var results = findChild(dropdown, "focusDropdownResults")
      verify(results !== null)
      phase = "results count"
      tryCompare(results, "count", 3)
      // Filtering from the preceding test can leave delegate geometry pending.
      // Send pointer events only once the new list is laid out and rendered.
      waitForPolish(window)
      waitForRendering(results)
      phase = "find second row"
      var row = results.itemAtIndex(1)
      verify(row !== null)
      phase = "mouse move"
      mouseMove(row, row.width / 2, row.height / 2)
      phase = "mouse click"
      mouseClick(row, row.width / 2, row.height / 2)
      phase = "click closed popup"
      tryCompare(dropdown, "popupOpen", false)
      phase = "correct selection " + dropdown.value
      compare(dropdown.value, "wind")
      phase = "selection signal"
      compare(selections.count, 1)
    }

    function cleanup() {
      if (qtest_results.failed)
        console.error("FAIL", qtest_results.functionName, phase)
      dropdown.close()
      tryCompare(findChild(dropdown, "focusDropdownPopup"), "visible", false)
    }

    function cleanupTestCase() {
      console.log("DROPDOWN_TEST_RESULT", JSON.stringify({
        passed: qtest_results.passCount,
        failed: qtest_results.failCount
      }))
    }
  }
}
