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
    property var commands: []
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(args) { lastArguments = args; commands = commands.concat([args]) }
  }
  Lofi.Panel { id: panel; anchors.fill: parent; hostWidget: host }
  TestCase {
    name: "SkylofiLayout"
    when: true
    property string phase: ""
    function visualItem(parent,name) {
      if (parent.objectName === name) return parent
      for (var child of parent.children || []) { var found = visualItem(child,name); if (found) return found }
      return null
    }
    function sourceCard(id) { return visualItem(findChild(panel,"section-body-nature"),"sourceCard-"+id) }
    function init() {
      phase = ""
      panel.editGuards = ({})
      panel.open()
      panel.showView(0)
      panel.libraryOpen = false
      panel.animationsEnabled = false
      panel.collapsed = ({})
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,station:"lofi-test",name:"Test radio",category:"lofi",category_name:"Lo-fi radio",main_volume:65,master_volume:80,mix:true,bg_station:"voice-test",bg_name:"Voice",nature_layers:[],animations:false}))
      panel.categories = [{id:"lofi",stations:[{id:"lofi-test",name:"Test radio",description:"Soft jazz"},{id:"lofi-second",name:"Second radio",description:"Dreamy beats"}]},{id:"talk",stations:[{id:"voice-test",name:"Voice"}]},{id:"ambience",stations:[{id:"noise-rain",name:"Rain"},{id:"noise-fireplace",name:"Fireplace"},{id:"noise-wind",name:"Wind"}]}]
      host.lastArguments = []
      host.commands = []
    }
    function xFor(slider,value) {
      var track = findChild(slider,"sliderTrack")
      return track.x + track.width * (value-slider.minimum) / (slider.maximum-slider.minimum)
    }
    function test_liveDragKeepsSourceObjectAndIgnoresStaleReplies() {
      panel.showView(1); panel.spatialEditorOpen = false; panel.natureCardExpanded = true
      var state = {running:true,paused:false,main_running:true,spatial_available:true,animations:false,
        imported_sounds:[],nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:30}]}
      panel.applyStatus(JSON.stringify(state))
      var card = sourceCard("noise-rain")
      var loader = findChild(card,"sourceDetailsLoader"), detail = loader.item
      var slider = findChild(findChild(card,"spaceCoverage"),"soundControlSlider")
      slider.forceActiveFocus(); wait(60); waitForPolish(window)
      var scroll = findChild(panel,"mixScroll"), offset = scroll.contentY
      phase = "live drag before release"
      host.commands = []
      mousePress(slider,xFor(slider,35),slider.height/2)
      for (var value=36; value<=55; value++) mouseMove(slider,xFor(slider,value),slider.height/2,1)
      wait(75)
      verify(slider.dragging)
      verify(host.commands.length >= 1 && host.commands.length <= 3,"Live drag must be bounded, not silent: "+host.commands.length)
      compare(host.commands[host.commands.length-1],["layer","noise-rain","coverage","55"])
      phase = "older status during grab"
      state.nature_layers[0].effective_volume = 12
      panel.applyStatus(JSON.stringify(state))
      compare(sourceCard("noise-rain"),card)
      compare(loader.item,detail)
      compare(slider.dragging,true)
      compare(slider.displayValue,55)
      compare(scroll.contentY,offset)
      compare(slider.activeFocus,true)
      mouseMove(slider,xFor(slider,72),slider.height/2)
      var beforeRelease = host.commands.length
      mouseRelease(slider,xFor(slider,72),slider.height/2)
      phase = "exact final release"
      compare(host.commands.length,beforeRelease+1)
      compare(host.commands[host.commands.length-1],["layer","noise-rain","coverage","72"])
      state.nature_layers[0].coverage = 72
      panel.applyStatus(JSON.stringify(state)) // Latest command ACK.
      state.nature_layers[0].coverage = 40
      panel.applyStatus(JSON.stringify(state)) // Older in-flight snapshot.
      compare(slider.displayValue,72)
      compare(panel.natureLayer("noise-rain").coverage,72)
      wait(320)
      compare(slider.displayValue,72)
      compare(host.commands.length,beforeRelease+1)
      compare(sourceCard("noise-rain"),card)
    }
    function test_everySliderFamilyAppliesBeforeReleaseAndSeekCancelsOnRadio() {
      panel.showView(1)
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,spatial_available:true,
        animations:false,wander:{enabled:true,amount:20},room:{preset:"cozy",size:35,softness:55,reflections:25},
        fade_enabled:true,ducking:true,nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:50}]}))
      var sliders = [
        {item:findChild(findChild(panel,"allSoundsLevel"),"levelSlider"),value:64,args:["vol","master","64"],view:1},
        {item:findChild(findChild(panel,"soundtrackLevel"),"levelSlider"),value:46,args:["vol","main","46"],view:1},
        {item:findChild(panel,"livingMixSlider"),value:44,args:["wander-amount","44"],view:1},
        {item:findChild(findChild(panel,"fadeDuration"),"settingSlider"),value:6,args:["ui","fadeSeconds","6"],view:2},
        {item:findChild(findChild(panel,"dictationVolume"),"settingSlider"),value:48,args:["ui","duckLevel","48"],view:2}
      ]
      for (var test of sliders) {
        phase = "continuous "+test.args.join(" ")
        verify(test.item !== null)
        panel.showView(test.view); test.item.forceActiveFocus(); wait(40); waitForPolish(window)
        host.commands = []
        mousePress(test.item,xFor(test.item,test.value),test.item.height/2)
        wait(75)
        compare(host.commands,[test.args])
        mouseRelease(test.item,xFor(test.item,test.value),test.item.height/2)
        compare(host.commands,[test.args])
      }
      phase = "continuous finite timeline"
      panel.showView(0)
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,animations:false,
        category:"youtube",can_seek:true,main_position:20,main_duration:100,nature_layers:[]}))
      var seek = findChild(panel,"playbackProgress")
      seek.forceActiveFocus(); waitForPolish(window); host.commands = []
      mousePress(seek,xFor(seek,40),seek.height/2); wait(140)
      verify(Math.abs(seek.displayValue-40) < 0.5)
      var seekCommand = ["seek",String(seek.displayValue)]
      compare(host.commands,[seekCommand])
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,animations:false,
        category:"lofi",can_seek:false,nature_layers:[]}))
      mouseRelease(seek,xFor(seek,40),seek.height/2)
      wait(150)
      compare(host.commands,[seekCommand])
    }
    function test_soloButtonIsAvailableOnCollapsedCardAndBannerSurvivesSelection() {
      panel.showView(1); panel.spatialEditorOpen = false; panel.natureCardExpanded = false
      var state = {running:true,paused:false,main_running:true,spatial_available:true,animations:false,
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:100},{id:"noise-fireplace",enabled:true,volume:50,coverage:12}]}
      panel.applyStatus(JSON.stringify(state))
      var card = sourceCard("noise-fireplace"), solo = findChild(card,"sourceSolo-noise-fireplace")
      verify(solo.visible && solo.enabled)
      panel.ensureVisible(findChild(panel,"mixScroll"),solo); waitForPolish(window)
      mouseClick(solo,solo.width/2,solo.height/2)
      compare(host.lastArguments,["audition","noise-fireplace","hold"])
      compare(panel.selectedNatureId,"noise-fireplace")
      compare(card.expanded,true)
      state.audition_id = "noise-fireplace"
      panel.applyStatus(JSON.stringify(state))
      sourceCard("noise-rain").selectedRequested()
      compare(panel.selectedNatureId,"noise-rain")
      compare(findChild(panel,"soloBanner").visible,true)
      var back = findChild(panel,"soloReturnToMix")
      mouseClick(back,back.width/2,back.height/2)
      compare(host.lastArguments,["audition","noise-fireplace","off"])
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
    function test_coverageCardKeyboardAndSingleSelection() {
      panel.showView(1)
      panel.spatialEditorOpen = false
      panel.natureCardExpanded = true
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,spatial_available:true,animations:false,
        nature_layers:[{id:"noise-rain",enabled:true,volume:35,coverage:30},
          {id:"noise-fireplace",enabled:true,volume:50,coverage:12,distance:18}]}))
      waitForPolish(window)
      var rain = sourceCard("noise-rain")
      verify(rain !== null)
      var coverage = findChild(rain,"spaceCoverage")
      var slider = findChild(coverage,"soundControlSlider")
      slider.forceActiveFocus()
      keyClick(Qt.Key_Right)
      compare(host.lastArguments,["layer","noise-rain","coverage","35"])
      keyClick(Qt.Key_Home)
      compare(host.lastArguments,["layer","noise-rain","coverage","0"])
      keyClick(Qt.Key_End)
      compare(host.lastArguments,["layer","noise-rain","coverage","100"])
      compare(panel.natureLayer("noise-rain").volume,35)
      var fire = sourceCard("noise-fireplace")
      var select = findChild(fire,"sourceSelect-noise-fireplace")
      panel.ensureVisible(findChild(panel,"mixScroll"),select)
      waitForPolish(window)
      host.commands = []
      mouseClick(select,select.width / 2,select.height / 2)
      compare(panel.selectedNatureId,"noise-fireplace")
      compare(fire.expanded,true)
      compare(rain.expanded,false)
      compare(host.commands,[])
    }
    function test_denseMapKeepsCoordinatesAndDragHasNoOffsetJump() {
      panel.showView(1)
      var layers = [], stations = []
      for (var index = 0; index < 16; index++) {
        var id = "noise-test-" + index
        layers.push({id:id,enabled:true,volume:25,coverage:50,pan:0,distance:0})
        stations.push({id:id,name:"Sound "+index})
      }
      panel.categories = [{id:"ambience",stations:stations}]
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,spatial_available:true,animations:false,nature_layers:layers}))
      panel.spatialEditorOpen = true
      waitForPolish(window)
      var stage = findChild(panel,"soundStage")
      compare(stage.sourceIds.length,16)
      compare(findChild(panel,"section-body-nature").height,0)
      var markers = []
      phase = "dense placement"
      for (var sound of layers) {
        var marker = visualItem(stage,"source-"+sound.id)
        verify(marker !== null)
        verify(marker.x >= 0 && marker.y >= 0)
        verify(marker.x + marker.width <= stage.width && marker.y + marker.height <= stage.height)
        compare(panel.natureLayer(sound.id).pan,0)
        compare(panel.natureLayer(sound.id).distance,0)
        for (var previous of markers) verify(Math.abs(marker.x - previous.x) >= marker.width || Math.abs(marker.y - previous.y) >= marker.height,"Dense map targets must not overlap")
        markers.push(marker)
      }
      var moved = markers[15]
      phase = "dense pointer selection"
      panel.ensureVisible(findChild(panel,"mixScroll"),stage)
      waitForPolish(window)
      host.commands = []
      var origin = moved.mapToItem(window.contentItem,moved.width / 2,moved.height / 2)
      mousePress(window.contentItem,origin.x,origin.y)
      compare(host.commands,[])
      phase = "dense status during drag"
      // Refresh effective levels during the grab; the marker object stays put.
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,spatial_available:true,animations:false,
        nature_layers:layers.map(function(layer) { return Object.assign({},layer,{effective_volume:12}) })}))
      compare(visualItem(stage,"source-"+layers[15].id),moved)
      mouseMove(window.contentItem,origin.x+8,origin.y-8)
      mouseRelease(window.contentItem,origin.x+8,origin.y-8)
      phase = "dense drag delta"
      compare(host.commands.length,2)
      compare(host.commands[0][2],"pan")
      compare(host.commands[1][2],"distance")
      verify(panel.natureLayer(layers[15].id).pan > 0 && panel.natureLayer(layers[15].id).pan < 15)
      verify(panel.natureLayer(layers[15].id).distance > 0 && panel.natureLayer(layers[15].id).distance < 15)
      // Keyboard movement works for the same displaced source.
      host.commands = []
      phase = "dense keyboard"
      moved.forceActiveFocus()
      keyClick(Qt.Key_Right)
      compare(host.commands.length,2)
      compare(host.commands[0][2],"pan")
    }
    function cleanup() {
      if (qtest_results.failed) console.error("LAYOUT FAILURE", qtest_results.functionName, phase)
    }
    function cleanupTestCase() {
      console.log("LAYOUT_TEST_RESULT", JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
