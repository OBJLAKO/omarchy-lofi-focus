import QtQuick
import QtQuick.Window
import QtTest
import qs.Commons
import "Plugin" as Lofi

Window {
  id: window
  width: @WIDTH@; height: @HEIGHT@; visible: true
  QtObject {
    id: host
    property string statusJson: ""
    property var lastArguments: []
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(arguments) { lastArguments = arguments }
  }
  Lofi.Panel { id: panel; anchors.fill: parent; hostWidget: host }
  Component { id: stackedLevel; Lofi.MixerLevel { animate: false; compact: true; removable: true; label: "Night crickets"; value: 100 } }
  TestCase {
    name: "SkylofiSliderGeometry"
    when: window.visible
    function initTestCase() {
      Style.fontBaseSize = @FONT@
      Style.spacingScale = 1
      Style.spacingScaleWithFont = true
      wait(100)
    }
    function init() {
      panel.showView(0)
      panel.open()
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,main_state:"playing",source_kind:"radio",station:"lofi-test",name:"Test radio",category:"lofi",main_volume:65,master_volume:80,mix:true,bg_station:"voice-test",bg_state:"playing",bg_volume:30,nature_layers:[{id:"noise-rain",enabled:true,volume:35},{id:"noise-fireplace",enabled:true,volume:20}],animations:false,fade_enabled:true,fade_seconds:3,ducking:true,duck_level:35}))
      panel.categories = [{id:"lofi",stations:[{id:"lofi-test",name:"Test radio"}]},{id:"talk",stations:[{id:"voice-test",name:"Voice"}]},{id:"ambience",stations:[{id:"noise-rain",name:"Rain"},{id:"noise-fireplace",name:"Fireplace"}]}]
      waitForPolish(window)
    }
    function collectSliders(item) {
      var result = []
      if (item.liveValue !== undefined && item.minimum !== undefined && item.maximum !== undefined) result.push(item)
      if (item.children) for (var child of item.children) result = result.concat(collectSliders(child))
      return result
    }
    function rectangleIn(item, reference) {
      var points = [item.mapToItem(reference,0,0), item.mapToItem(reference,item.width,0), item.mapToItem(reference,0,item.height), item.mapToItem(reference,item.width,item.height)]
      return {left:Math.min.apply(null,points.map(function(p){return p.x})),top:Math.min.apply(null,points.map(function(p){return p.y})),right:Math.max.apply(null,points.map(function(p){return p.x})),bottom:Math.max.apply(null,points.map(function(p){return p.y}))}
    }
    function expectInside(item, reference, message) {
      var box = rectangleIn(item, reference)
      var inside = box.left >= -0.1 && box.top >= -0.1 && box.right <= reference.width + 0.1 && box.bottom <= reference.height + 0.1
      if (!inside) console.error("SLIDER_GEOMETRY_ASSERT", message, JSON.stringify(box), "in", reference.width, reference.height)
      verify(inside,
        message + ": " + JSON.stringify(box) + " in " + reference.width + "×" + reference.height)
    }
    function verifyFocus(slider, viewport) {
      slider.forceActiveFocus()
      waitForPolish(window)
      var outline = findChild(slider, "sliderFocusOutline")
      verify(outline !== null, "Slider needs a visible focus outline")
      compare(outline.border.width, 1)
      expectInside(outline, slider, "Focus outline paints outside its hit target")
      if (viewport) expectInside(outline, viewport, "Focused slider is clipped by the scrolling page")
      expectInside(findChild(slider,"sliderThumb"), slider, "Focused thumb escapes its hit target")
    }
    function capture(name) {
      if (!"@OUT@") return
      var saved = false
      window.contentItem.grabToImage(function(result) { saved = result.saveToFile("@OUT@/" + name + ".png") })
      tryVerify(function(){return saved},2000)
    }
    function test_mixLevelsFocusWithinRowsAndViewport() {
      panel.showView(1)
      var viewport = findChild(panel,"mixScroll")
      var sliders = collectSliders(viewport)
      verify(sliders.length >= 4)
      for (var slider of sliders) {
        if (!slider.visible) continue
        verifyFocus(slider, viewport)
        expectInside(findChild(slider,"sliderFocusOutline"), slider.parent, "Focus border overlaps a neighboring level row")
      }
      capture("mix-focused-last-level")
    }
    function test_stackedLabelReadoutAndRemoveStayAboveFocusBorder() {
      var level = stackedLevel.createObject(window.contentItem, {x:10,y:10,width:Style.space(180)})
      verify(level !== null)
      verify(!level.inlineLevel)
      waitForPolish(window)
      var slider = findChild(level,"levelSlider")
      verifyFocus(slider, null)
      var focus = rectangleIn(findChild(slider,"sliderFocusOutline"), level)
      for (var name of ["levelLabel","levelReadout","removeSound"]) {
        var copy = findChild(level,name)
        expectInside(copy, level, "Stacked control escapes its row: " + name)
        var bounds = rectangleIn(copy, level)
        verify(focus.top > bounds.bottom, "Focused slider touches the label/readout/remove control: " + name)
      }
      expectInside(slider, level, "Stacked slider escapes its row")
      level.destroy()
    }
    function test_tabbingBetweenStackedLevelActionsRevealsTheFocusedControl() {
      panel.showView(1)
      var viewport = findChild(panel,"mixScroll")
      var level = findChild(panel,"natureLevel-noise-fireplace")
      var slider = findChild(level,"levelSlider")
      var remove = findChild(level,"removeSound")
      verifyFocus(slider,viewport)
      keyClick(Qt.Key_Tab)
      tryCompare(remove,"activeFocus",true)
      expectInside(remove,viewport,"Tab from slider leaves the remove action clipped")
      keyClick(Qt.Key_Backtab)
      tryCompare(slider,"activeFocus",true)
      expectInside(findChild(slider,"sliderFocusOutline"),viewport,"Backtab from remove leaves the slider clipped")
    }
    function test_allSoundsFocusFitsPersistentDockOnEveryTab() {
      var dock = findChild(panel,"playbackDock")
      var master = findChild(findChild(panel,"allSoundsLevel"),"levelSlider")
      for (var index=0; index<3; index++) {
        panel.showView(index)
        verifyFocus(master, null)
        expectInside(findChild(master,"sliderFocusOutline"), dock, "Overall volume outline escapes the dock")
        expectInside(findChild(master,"sliderFocusOutline"), window.contentItem, "Overall volume outline is clipped by the window")
        capture("master-focused-tab-" + index)
      }
    }
    function test_settingsFocusedSlidersDoNotTouchCaptions() {
      panel.showView(2)
      var viewport = findChild(panel,"settingsScroll")
      var sliders = collectSliders(viewport)
      verify(sliders.length >= 2)
      for (var slider of sliders) {
        if (!slider.visible) continue
        verifyFocus(slider, viewport)
        var focus = rectangleIn(findChild(slider,"sliderFocusOutline"), slider.parent)
        for (var sibling of slider.parent.children) {
          if (sibling === slider || sibling.height <= 0 || !sibling.visible) continue
          var box = rectangleIn(sibling,slider.parent)
          verify(focus.top > box.bottom, "Settings slider border touches the preceding caption")
        }
      }
      capture("settings-focused-dictation-level")
    }
    function test_finiteTimelineFocusAndPointerEndpoints() {
      panel.applyStatus(JSON.stringify({running:true,paused:false,main_running:true,main_state:"playing",station:"youtube-test",name:"Recording",category:"youtube",source_kind:"recording",can_seek:true,main_position:120,main_duration:300,animations:false}))
      var slider = findChild(panel,"playbackProgress")
      verify(slider.visible)
      verifyFocus(slider,null)
      var controls = findChild(panel,"finitePlaybackControls")
      var focus = rectangleIn(findChild(slider,"sliderFocusOutline"),controls)
      expectInside(findChild(slider,"sliderFocusOutline"),controls,"Timeline outline escapes its dock group")
      for (var child of controls.children) {
        if (child === slider || !child.visible) continue
        verify(focus.top > rectangleIn(child,controls).bottom, "Timeline outline touches elapsed/total time")
      }
      capture("recording-focused-timeline")
      mouseClick(slider,0,slider.height/2)
      compare(host.lastArguments,["seek","0"])
      mouseClick(slider,slider.width-1,slider.height/2)
      compare(host.lastArguments,["seek","300"])
    }
    function cleanupTestCase() {
      console.log("SLIDER_GEOMETRY_RESULT",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
