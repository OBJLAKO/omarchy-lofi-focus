import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi
Window {
  id: window
  width: 430; height: 640; visible: true
  QtObject {
    id: host
    property string statusJson: ""
    property var lastArguments: []
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(args) { lastArguments = args }
  }
  Lofi.Panel { id: panel; anchors.fill: parent; hostWidget: host }
  TestCase {
    name: "SkylofiLayout"
    when: true
    function init() {
      panel.open()
      panel.showView(0)
      panel.libraryOpen = false
      panel.animationsEnabled = false
      panel.collapsed = ({})
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,station:"lofi-test",name:"Test radio",category:"lofi",category_name:"Lo-fi radio",main_volume:65,master_volume:80,mix:true,bg_station:"voice-test",bg_name:"Voice",nature_layers:[],animations:false}))
      panel.categories = [{id:"lofi",stations:[{id:"lofi-test",name:"Test radio",description:"Soft jazz"},{id:"lofi-second",name:"Second radio",description:"Dreamy beats"}]},{id:"talk",stations:[{id:"voice-test",name:"Voice"}]},{id:"ambience",stations:[{id:"noise-rain",name:"Rain"},{id:"noise-fireplace",name:"Fireplace"},{id:"noise-wind",name:"Wind"}]}]
      host.lastArguments = []
    }
    function test_natureAddedAfterEmptySectionRemainsVisible() {
      var body = findChild(panel, "section-body-nature")
      verify(body !== null)
      panel.natureLayers = [{id:"noise-rain",enabled:true,volume:30}]
      tryVerify(function() { return body.height > 0 }, 1000)
      panel.toggleCollapsed("nature")
      tryCompare(body, "height", 0)
      panel.toggleCollapsed("nature")
      tryVerify(function() { return body.height > 0 }, 1000)
    }
    function test_mixAddSoundFitsCompactPanel() {
      panel.showView(1)
      panel.natureLayers = [{id:"noise-rain",enabled:true,volume:30},{id:"noise-fireplace",enabled:true,volume:20}]
      var picker = findChild(panel, "naturePicker")
      verify(picker !== null)
      verify(picker.visible)
      waitForPolish(window)
      var point = picker.mapToItem(window.contentItem, 0, picker.height)
      verify(point.y <= window.height, "Add sound must fit: " + point.y)
    }
    function test_stationSearchFiltersNameAndDescription() {
      var search = findChild(panel, "stationSearch")
      search.text = "dreamy"
      tryCompare(findChild(panel, "station-lofi-test"), "visible", false)
      tryCompare(findChild(panel, "station-lofi-second"), "visible", true)
      search.text = ""
      tryCompare(findChild(panel, "station-lofi-test"), "visible", true)
    }
    function test_keyboardTabsAndSearch() {
      var settings = findChild(panel, "mainTab-2")
      settings.forceActiveFocus()
      keyClick(Qt.Key_Return)
      compare(panel.currentView, 2)
      keyClick(Qt.Key_1, Qt.ControlModifier)
      compare(panel.currentView, 0)
      keyClick(Qt.Key_F, Qt.ControlModifier)
      tryCompare(findChild(panel, "stationSearch"), "activeFocus", true)
    }
    function test_keyboardVolumeSendsCorrectChannel() {
      panel.showView(1)
      var level = findChild(panel, "soundtrackLevel")
      var slider = findChild(level, "levelSlider")
      slider.forceActiveFocus()
      keyClick(Qt.Key_Right)
      compare(host.lastArguments, ["vol", "main", "70"])
      keyClick(Qt.Key_Home)
      compare(host.lastArguments, ["vol", "main", "0"])
    }
    function cleanup() {
      if (qtest_results.failed) console.error("LAYOUT FAILURE", qtest_results.functionName)
    }
    function cleanupTestCase() {
      console.log("LAYOUT_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
