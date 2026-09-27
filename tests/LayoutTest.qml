import QtQuick
import QtQuick.Window
import QtTest
import "Plugin" as Lofi
Window {
 width:468; height:860; visible:true
 Lofi.Panel {id:panel;anchors.fill:parent}
 TestCase {
  name:"FocusLayout"
  when:true
    function test_natureAddedAfterEmptySectionRemainsVisible() {
      panel.animationsEnabled = false
      panel.collapsed = ({})
      panel.natureLayers = []
      panel.categories = [{id:"ambience", stations:[{id:"noise-rain",name:"Rain"}]}]
      var body = findChild(panel, "section-body-nature")
      verify(body !== null)
      panel.natureLayers = [{id:"noise-rain",enabled:true,volume:30}]
      tryVerify(function(){return body.height > 0}, 1000, "Expanded nature height=" + body.height)
      panel.toggleCollapsed("nature")
      tryCompare(body, "height", 0)
      panel.toggleCollapsed("nature")
      tryVerify(function(){return body.height > 0}, 1000, "Expanded nature height=" + body.height)
    }

  function cleanupTestCase(){console.log("LAYOUT_TEST_RESULT",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))}
 }
}
