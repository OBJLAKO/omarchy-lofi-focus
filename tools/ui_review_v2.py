#!/usr/bin/env python3
"""Independent pointer/keyboard review and real QML screenshots, without audio.

Only layer-shell placement is replaced. The temporary surface reproduces the
production card's size, border, padding and content insets. HOME, XDG directories
and D-Bus are isolated; the fixture host records commands and never executes them.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
SURFACE = r'''import QtQuick
import qs.Commons
import qs.Ui
BorderSurface {
  id: surface
  property var anchorItem
  property var owner
  property var bar
  property bool open
  property bool centerOnBar
  property var focusTarget
  property real contentWidth
  property real contentHeight
  default property alias contentItem: holder.children
  width: contentWidth; height: contentHeight
  x: (parent.width-width)/2; y: (parent.height-height)/2
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  radius: Style.cornerRadius
  function fittedContentWidth(value) { return Math.min(value, parent.width-20) }
  function fittedContentHeight(value) { return Math.min(value, parent.height-20) }
  onOpenChanged: if (open) Qt.callLater(function(){ if(focusTarget) focusTarget.forceActiveFocus() })
  Item {
    id: holder
    anchors.fill: parent
    anchors.leftMargin: surface.contentLeftInset
    anchors.rightMargin: surface.contentRightInset
    anchors.topMargin: surface.contentTopInset
    anchors.bottomMargin: surface.contentBottomInset
  }
}
'''
QML = r'''import QtQuick
import QtQuick.Window
import QtTest
import qs.Commons
import "Plugin" as Lofi
Window {
  id: win; width: @WIDTH@; height: @HEIGHT@; visible: true; color: Color.background
  QtObject {
    id: fixtureBar
    property color foreground: Color.foreground
    property color background: Color.popups.background
    property color barForeground: foreground
    property string fontFamily: Style.font.family
  }
  QtObject {
    id: host
    property string statusJson: ""
    property var lastArguments: []
    property var commands: []
    signal actionFinished(var arguments, int exitCode, string message)
    function runAction(args) { lastArguments=args; commands=commands.concat([args]) }
  }
  Lofi.Panel { id: panel; anchors.fill: parent; hostWidget: host; bar: fixtureBar }
  TestCase {
    name: "SkylofiIndependentReview"; when: win.visible
    property var originalCategories: []
    property bool captured: false
    function item(name) { var found=findChild(panel,name); expect(found !== null, "Missing control " + name); return found }
    function initTestCase() {
      Style.fontBaseSize=@FONT@; Style.spacingScale=1; Style.spacingScaleWithFont=true
      Style.cornerRadius=6
      Color.foreground=@FG@; Color.background=@BG@; Color.accent=@ACCENT@; Color.urgent="#c65c5c"
      wait(100)
      originalCategories=panel.categories
      expect(originalCategories.length > 0)
    }
    function state(extra) {
      var value={running:true,paused:false,main_running:true,main_state:"playing",source_kind:"radio",station:"lofi-lilo",name:"Lilo-Fi Radio",category:"lofi",category_name:"Lo-fi radio",main_title:"Live radio metadata",main_position:30,main_duration:120,can_seek:false,main_volume:65,master_volume:80,mix:true,bg_station:"voice-changelog",bg_name:"The Changelog",bg_state:"playing",bg_volume:30,youtube_available:true,youtube_entries:[{id:"youtube-demo",name:"A conversation for a rainy day",is_live:false,position:1240},{id:"youtube-demo2",name:"Sunday morning jazz",is_live:false,position:0}],nature_layers:[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:35},{id:"noise-fireplace",name:"Fireplace",enabled:true,running:true,volume:20}],animations:false,fade_enabled:true,fade_seconds:3,ducking:true,duck_level:35}
      host.statusJson=JSON.stringify(Object.assign(value,extra || {}))
      panel.applyStatus(host.statusJson)
    }
    function init() {
      panel.open(); panel.showView(0); panel.libraryOpen=false
      fixtureBar.fontFamily=Style.font.family
      panel.categories=originalCategories
      panel.youtubeEntries=[]
      panel.libraryMessage=""; panel.libraryError=false; panel.actionMessage=""
      item("youtubeLibrary").addingLink=false; item("youtubeLibrary").pendingRemoval=""
      item("stationSearch").text=""
      state()
      for (var name of ["listenScroll","mixScroll","settingsScroll"]) item(name).contentY=0
      host.lastArguments=[]; host.commands=[]
      waitForPolish(win)
      wait(50)
    }
    function shot(name) {
      mouseMove(win.contentItem,win.width/2,20)
      waitForPolish(win); wait(40)
      captured=false
      win.contentItem.grabToImage(function(result) { captured=result.saveToFile("@OUT@/"+name+".png") })
      eventually(this,"captured",true,2000)
    }
    function click(name) { var control=item(name); mouseClick(control,control.width/2,control.height/2) }
    function typeText(text) { for (var character of text) keyClick(character) }
    function popupFits(picker) {
      var popup=findChild(picker,"focusDropdownPopup"); expect(popup !== null)
      var origin=popup.contentItem.mapToItem(win.contentItem,0,0)
      expect(origin.x>=8 && origin.y>=8,"popup top-left outside card: "+origin)
      expect(origin.x+popup.contentItem.width<=win.width-8,"popup right outside card: "+origin.x+"+"+popup.contentItem.width)
      expect(origin.y+popup.contentItem.height<=win.height-8,"popup bottom outside card: "+origin.y+"+"+popup.contentItem.height)
    }
    function controlWithProperty(parent,property) {
      if(parent[property] !== undefined) return parent
      if(!parent.children) return null
      for(var child of parent.children) {var found=controlWithProperty(child,property);if(found)return found}
      return null
    }
    function knobFor(parent,size) {
      if(parent.width===size && parent.height===size) return parent
      if(!parent.children) return null
      for(var child of parent.children) {var found=knobFor(child,size);if(found)return found}
      return null
    }
    function indicators(parent) {
      var found=[]
      if(parent.moving !== undefined && parent.ink !== undefined) found.push(parent)
      if(parent.children) for(var child of parent.children) found=found.concat(indicators(child))
      return found
    }
    function expect(cond,message) {
      if(!cond) console.error("REVIEW ASSERT",qtest_results.functionName,message || "condition was false")
      verify(cond,message || "condition was false")
    }
    function expectEq(actual,expected,message) {
      if(JSON.stringify(actual)!==JSON.stringify(expected)) console.error("REVIEW COMPARE",qtest_results.functionName,JSON.stringify(actual),JSON.stringify(expected),message || "")
      compare(actual,expected,message || "")
    }
    function eventually(object,property,expected,timeout) {
      var end=Date.now()+(timeout || 5000)
      while(JSON.stringify(object[property])!==JSON.stringify(expected)&&Date.now()<end) wait(20)
      expectEq(object[property],expected,"property="+property)
    }

    function test_radioLiveAndControls() {
      expectEq(panel.hasProgress,false)
      expectEq(item("finitePlaybackControls").visible,false)
      expect(findChild(panel,"previousSource") === null)
      expect(findChild(panel,"nextSource") === null)
      click("togglePlayback"); expectEq(host.lastArguments,["toggle"])
      click("stopPlayback"); expectEq(host.lastArguments,["stop"])
      shot("radio-live")
    }
    function test_tabsKeepDockAndNavigationStable() {
      var nav=item("mainNavigation"), dock=item("playbackDock")
      var navY=nav.mapToItem(win.contentItem,0,0).y
      var dockY=dock.mapToItem(win.contentItem,0,0).y
      for (var index=0; index<3; index++) {
        click("mainTab-"+index); expectEq(panel.currentView,index)
        waitForPolish(win); wait(40)
        expectEq(nav.mapToItem(win.contentItem,0,0).y,navY)
        expectEq(dock.mapToItem(win.contentItem,0,0).y,dockY)
        if(index===1 && !@COMPACT@) {
          var scroll=item("mixScroll")
          for(var layer of panel.natureLayers) {
            if(!layer.enabled) continue
            var level=item("natureLevel-"+layer.id)
            var control=findChild(level,"levelSlider")
            expect(control !== null)
            var position=control.mapToItem(scroll,0,0)
            expect(position.y>=0 && position.y+control.height<=scroll.height,"Enabled slider clipped in the normal panel: "+layer.id+",y="+position.y+",height="+control.height+",viewport="+scroll.height)
          }
        }
        shot(["listen","mix-two-layers","settings"][index])
      }
      var originalFont=fixtureBar.fontFamily
      fixtureBar.fontFamily="sans-serif"
      waitForPolish(win); wait(40)
      expectEq(item("togglePlayback").fontFamily,"sans-serif","Dock action must inherit the bar font")
      expectEq(item("saveYoutube").fontFamily,"sans-serif","Library action must inherit the bar font")
      var removeControl=controlWithProperty(item("natureLevel-noise-rain"),"tooltipText")
      expect(removeControl !== null)
      expectEq(removeControl.fontFamily,"sans-serif","Nature action must inherit the bar font")
      fixtureBar.fontFamily=originalFont
    }
    function test_youtubeSeekUsesRealKeys() {
      state({station:"youtube-demo",name:"A conversation for a rainy day",source_kind:"recording",category:"youtube",category_name:"YouTube",main_title:"A conversation for a rainy day",main_position:1240,main_duration:3840,can_seek:true})
      panel.libraryOpen=true
      expectEq(panel.hasProgress,true)
      var progress=item("playbackProgress"); progress.forceActiveFocus()
      keyClick(Qt.Key_Right); expectEq(host.lastArguments,["seek","1255"])
      keyClick(Qt.Key_Left); expectEq(host.lastArguments,["seek","1225"])
      shot("youtube-seek")
    }
    function test_emptyLibraryFormAndCancel() {
      panel.libraryOpen=true; panel.youtubeEntries=[]
      shot("library-empty")
      var library=item("youtubeLibrary")
      if (!library.addingLink) click("addYoutube")
      panel.youtubeUrl.text="https://youtu.be/jNQXAC9IVRw"
      panel.youtubeTitle.text="Rainy day conversation"
      shot("library-add")
      panel.youtubeTitle.forceActiveFocus(); keyClick(Qt.Key_Escape)
      expectEq(panel.opened,true)
      expectEq(library.addingLink,false)
    }
    function test_savedLibraryFilterAndRemoval() {
      panel.libraryOpen=true
      panel.youtubeEntries=[{id:"youtube-demo",name:"A conversation for a rainy day",position:1240},{id:"youtube-demo2",name:"Sunday morning jazz",position:0},{id:"youtube-demo3",name:"Forest piano",position:0},{id:"youtube-demo4",name:"After hours jazz",position:500},{id:"youtube-demo5",name:"Quiet coding",position:0}]
      keyClick(Qt.Key_F,Qt.ControlModifier)
      var search=item("librarySearch"); eventually(search,"activeFocus",true)
      typeText("jazz")
      shot("library-filter")
      var savedRow=controlWithProperty(item("libraryEntry-youtube-demo2"),"name")
      expect(savedRow !== null)
      savedRow.forceActiveFocus()
      panel.ensureVisible(item("listenScroll"),savedRow)
      waitForPolish(win); wait(40)
      mouseClick(savedRow,savedRow.width/2,savedRow.height/2)
      expectEq(host.lastArguments,["start","youtube-demo2"])
      search.text=""
      var remove=item("removeYoutube-youtube-demo")
      remove.forceActiveFocus()
      waitForPolish(win); wait(40)
      click("removeYoutube-youtube-demo")
      expectEq(item("youtubeLibrary").pendingRemoval,"youtube-demo")
      shot("library-remove")
      search.forceActiveFocus(); keyClick(Qt.Key_Escape)
      // A field consumes its first Escape. The next Escape dismisses confirmation.
      if (item("youtubeLibrary").pendingRemoval.length > 0) keyClick(Qt.Key_Escape)
      expectEq(item("youtubeLibrary").pendingRemoval,"")
      expectEq(panel.opened,true)
      item("youtubeLibrary").pendingRemoval="youtube-demo"
      var confirm=item("confirmRemoveYoutube-youtube-demo")
      confirm.forceActiveFocus(); waitForPolish(win); wait(40)
      click("confirmRemoveYoutube-youtube-demo")
      expectEq(host.lastArguments,["youtube-remove","youtube-demo"])
    }
    function test_naturePickerPointerFilterKeyboard() {
      panel.showView(1)
      var picker=item("naturePicker")
      var scroll=item("mixScroll")
      panel.ensureVisible(scroll,picker); waitForPolish(win)
      click("naturePicker"); eventually(picker,"popupOpen",true)
      var search=findChild(picker,"focusDropdownSearch"); expect(search !== null)
      eventually(search,"activeFocus",true)
      typeText("ocean")
      shot("nature-picker")
      popupFits(picker)
      expect(picker.filtered.length > 0)
      var selected=picker.filtered[0].value
      keyClick(Qt.Key_Return)
      eventually(picker,"popupOpen",false)
      expectEq(host.lastArguments,["nature",selected,"on"])
    }
    function test_voicePickerAndFailure() {
      panel.showView(1)
      var picker=item("voicePicker")
      waitForPolish(win); wait(40)
      picker.forceActiveFocus()
      panel.ensureVisible(item("mixScroll"),picker)
      waitForPolish(win); wait(40)
      click("voicePicker"); eventually(picker,"popupOpen",true)
      shot("voice-picker")
      popupFits(picker)
      typeText("off"); keyClick(Qt.Key_Return)
      eventually(picker,"popupOpen",false)
      expectEq(host.lastArguments,["bg","off"])
      state({bg_state:"loading"}); shot("voice-loading")
      state({bg_state:"failed",bg_error:"Podcast unavailable: the server did not respond. Try again or choose another source."})
      waitForPolish(win); wait(40)
      expect(item("voiceRetry").visible)
      item("voiceRetry").forceActiveFocus()
      panel.ensureVisible(item("mixScroll"),item("voiceRetry"))
      waitForPolish(win); wait(40)
      click("voiceRetry"); expectEq(host.lastArguments,["bg","voice-changelog"])
      shot("voice-failed")
    }
    function test_longTextAndNineLayersCanScroll() {
      var long="An exceptionally long programme name — разговор для дождливого вечера — "
      state({name:long.repeat(3),main_title:long.repeat(3)})
      shot("long-radio-title")
      panel.showView(1)
      var layers=[]
      for(var entry of panel.noiseOptions) layers.push({id:entry.value,name:entry.label,enabled:true,running:true,volume:35})
      panel.natureLayers=layers
      var scroll=item("mixScroll")
      waitForPolish(win); wait(40)
      expect(scroll.contentHeight > scroll.height)
      host.commands=[]
      mouseWheel(scroll,scroll.width/2,scroll.height/2,0,-960)
      wait(100)
      expect(scroll.contentY>0,"Wheel did not scroll the overflowing mixer")
      expectEq(host.commands,[],"Unfocused wheel must not change audio levels")
      scroll.contentY=scroll.contentHeight-scroll.height
      shot("mix-all-layers-bottom")
      var dock=item("playbackDock")
      expect(dock.mapToItem(win.contentItem,0,dock.height).y<=win.height)
    }
    function test_keyboardNavigationVolumeAndScroll() {
      click("mainTab-2"); keyClick(Qt.Key_2,Qt.ControlModifier)
      expectEq(panel.currentView,1)
      var slider=findChild(item("soundtrackLevel"),"levelSlider"); expect(slider !== null)
      slider.forceActiveFocus(); keyClick(Qt.Key_Right)
      expectEq(host.lastArguments,["vol","main","70"])
      keyClick(Qt.Key_Home); expectEq(host.lastArguments,["vol","main","0"])
      keyClick(Qt.Key_1,Qt.ControlModifier); keyClick(Qt.Key_F,Qt.ControlModifier)
      eventually(item("stationSearch"),"activeFocus",true)
      typeText("jazz")
      shot("radio-search")
      keyClick(Qt.Key_Escape)
      expectEq(item("stationSearch").text,"")
      expectEq(panel.opened,true)
    }
    function test_keyboardFocusRevealsEveryLayer() {
      panel.showView(1)
      var layers=[]
      for(var entry of panel.noiseOptions) layers.push({id:entry.value,name:entry.label,enabled:true,running:true,volume:35})
      panel.natureLayers=layers
      waitForPolish(win); wait(40)
      var scroll=item("mixScroll")
      item("mainTab-1").forceActiveFocus()
      var visited=0
      for (var step=0;step<30;step++) {
        keyClick(Qt.Key_Tab); waitForPolish(win); wait(15)
        var focus=win.activeFocusItem
        var ancestor=focus
        while(ancestor && ancestor!==scroll) ancestor=ancestor.parent
        if(ancestor===scroll) {
          visited++
          var origin=focus.mapToItem(scroll,0,0)
          expect(origin.y>=-1 && origin.y+focus.height<=scroll.height+1,"Tab focused a clipped mix control at y="+origin.y+",height="+focus.height+",viewport="+scroll.height)
        }
      }
      expect(visited>=layers.length,"Tab failed to reach every active nature layer; visited="+visited)
      shot("mix-keyboard-last-focus")
    }
    function test_unknownSavedSourceHasNoSeek() {
      state({station:"youtube-live",name:"Saved audio of unknown type",source_kind:"unknown",category:"youtube",main_duration:7200,main_position:45,can_seek:false,youtube_entries:[{id:"youtube-live",name:"Saved audio of unknown type",position:45}]})
      panel.libraryOpen=true
      expectEq(panel.hasProgress,false)
      expectEq(item("finitePlaybackControls").visible,false)
      shot("saved-unknown-no-seek")
      state({station:"youtube-live",name:"Saved live mix",source_kind:"live",category:"youtube",main_duration:7200,main_position:45,can_seek:false,youtube_entries:[{id:"youtube-live",name:"Saved live mix",is_live:true,position:45}]})
      expectEq(panel.hasProgress,false)
      shot("saved-live-no-seek")
    }
    function test_linkSaveFailurePreservesFields() {
      panel.libraryOpen=true
      item("youtubeLibrary").addingLink=true
      panel.youtubeUrl.text="https://youtu.be/jNQXAC9IVRw"
      panel.youtubeTitle.text="Rainy day conversation"
      waitForPolish(win); wait(40)
      item("saveYoutube").forceActiveFocus()
      panel.ensureVisible(item("listenScroll"),item("saveYoutube"))
      waitForPolish(win); wait(40)
      click("saveYoutube")
      expectEq(host.lastArguments,["youtube-add","https://youtu.be/jNQXAC9IVRw","Rainy day conversation"])
      host.actionFinished(host.lastArguments,1,"Could not save this link. Check the YouTube URL.")
      expectEq(panel.youtubeUrl.text,"https://youtu.be/jNQXAC9IVRw")
      expectEq(item("youtubeLibrary").addingLink,true)
      shot("library-save-failed")
      state({youtube_available:false}); shot("library-missing-extractor")
    }
    function test_settingsActionsAndReducedMotionSwitch() {
      panel.showView(2)
      var row=item("fadeToggle")
      waitForPolish(win); wait(40)
      panel.ensureVisible(item("settingsScroll"),row)
      var toggle=controlWithProperty(row,"checked")
      if(toggle===row) {
        toggle=null
        for(var child of row.children) {var found=controlWithProperty(child,"checked");if(found){toggle=found;break}}
      }
      expect(toggle !== null,"fade switch missing")
      mouseClick(toggle,toggle.width/2,toggle.height/2)
      expectEq(host.lastArguments,["ui","fade","off"])
      panel.animationsEnabled=false
      var legacy=controlWithProperty(toggle,"knobSize")
      var motionStillActive=false
      var motionDetails=""
      if(legacy) {
        var knob=knobFor(legacy,legacy.knobSize)
        expect(knob !== null,"switch knob missing")
        panel.fadeEnabled=false
        wait(10)
        motionStillActive=Math.abs(knob.x-legacy.knobInset)>=0.1
        motionDetails="Motion off still animates switch: x="+knob.x+",target="+legacy.knobInset
      } else {
        panel.fadeEnabled=false
      }
      shot("settings-fade-off")
      var slider=item("dictationVolume")
      panel.ensureVisible(item("settingsScroll"),slider)
      shot("settings-dictation")
      item("settingsScroll").contentY=item("settingsScroll").contentHeight-item("settingsScroll").height
      shot("settings-interface")
      expect(!motionStillActive,motionDetails)
    }
    function test_playbackStatesAndReducedMotion() {
      for (var s of ["stopped","connecting","reconnecting","failed","ended"]) {
        var extra={running:s!=="stopped",main_running:s!=="stopped",main_state:s,main_retry_count:2,main_retry_at:0}
        if(s==="ended") Object.assign(extra,{source_kind:"recording",category:"youtube",station:"youtube-demo",name:"A conversation for a rainy day",main_title:"A conversation for a rainy day",can_seek:true,main_duration:3840,main_position:3840})
        state(extra)
        shot("state-"+s)
      }
      state({paused:true}); shot("state-paused")
      panel.animationsEnabled=false; expectEq(panel.liveMotion,false)
      panel.close(); expectEq(panel.liveMotion,false)
    }
    function test_indicatorStopsForPauseClosedAndReducedMotion() {
      state({animations:true,equalizer:true,paused:true})
      state({animations:true,equalizer:true})
      var waves=indicators(panel)
      expect(waves.length>0,"Expected a playback state indicator")
      expect(waves.some(function(wave){return wave.moving}),"Playing indicator did not animate")
      wait(400)
      expect(waves.some(function(wave){return wave.moving}),"Playing indicator stopped while audio is active")
      var before=waves.map(function(wave){return wave.frameCount})
      wait(1000)
      expect(waves.some(function(wave,index){return wave.frameCount>before[index]}),"Playing indicator has no ongoing updates")
      expect(waves.every(function(wave,index){return wave.frameCount-before[index]<=10}),"Playing indicator exceeds its low-rate update budget")
      state({animations:true,master_volume:0})
      expect(waves.every(function(wave){return !wave.moving}),"Muted mix still animates")
      state({animations:true,main_running:false,main_state:"reconnecting",bg_running:false,bg_state:"stopped",nature_layers:[]})
      expect(waves.every(function(wave){return !wave.moving}),"Connection retry alone still animates")
      state({animations:true,main_volume:0,bg_running:false,bg_state:"stopped",nature_layers:[]})
      expect(waves.every(function(wave){return !wave.moving}),"Silent foreground still animates")
      state({animations:true,main_running:false,main_state:"ended",bg_running:true,bg_state:"playing",nature_layers:[]})
      expect(waves.some(function(wave){return wave.moving}),"Audible voice lost its indicator when music ended")
      state({animations:true,main_running:false,main_state:"reconnecting",bg_running:false,bg_state:"stopped"})
      expect(waves.some(function(wave){return wave.moving}),"Audible nature lost its indicator while music reconnects")
      state({animations:true,equalizer_animation:false})
      expect(waves.every(function(wave){return !wave.moving}),"Playback-indicator preference did not stop motion")
      state({animations:true,equalizer:true,paused:true})
      expect(waves.every(function(wave){return !wave.moving}),"Paused indicator is still moving")
      state({animations:true,equalizer:true})
      panel.animationsEnabled=false
      expect(waves.every(function(wave){return !wave.moving}),"Reduced motion did not stop indicator")
      panel.animationsEnabled=true
      panel.close()
      expect(waves.every(function(wave){return !wave.moving}),"Closed panel has a running indicator")
    }
    function cleanup() {
      for(var name of ["voicePicker","naturePicker"]) {var picker=findChild(panel,name);if(picker)picker.close()}
      if(qtest_results.failed) console.error("INDEPENDENT REVIEW FAILURE",qtest_results.functionName)
    }
    function cleanupTestCase() {
      console.log("UI_REVIEW_RESULT",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}))
    }
  }
}
'''


def run(variant, destination, sources, catalog):
    font = {"scale125": 15, "scale150": 18, "compact150": 18}.get(variant, 12)
    factor = font / 12
    compact = variant in ("compact", "compact150")
    width = 430 if compact else round(460 * factor) + 20
    height = 480 if compact else round(600 * factor) + 20
    colors = ("#24282d", "#f6f7f8", "#326d9b") if variant == "light" else ("#d8dde1", "#14191e", "#86b4d3")
    output_dir = destination / variant
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="skylofi-v2-review-") as directory:
        stage = Path(directory)
        for name in ("Commons", "Ui"):
            (stage / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
        plugin = stage / "Plugin"
        plugin.mkdir()
        for name, contents in sources.items():
            (plugin / name).write_bytes(contents)
        (plugin / "stations.json").write_bytes(catalog)
        panel = plugin / "Panel.qml"
        panel.write_text(panel.read_text().replace("KeyboardPanel {", "PreviewSurface {"))
        (plugin / "PreviewSurface.qml").write_text(SURFACE)
        qml = QML
        for token, value in {"WIDTH": width, "HEIGHT": height, "FONT": font, "OUT": str(output_dir), "COMPACT": str(compact).lower(), "FG": json.dumps(colors[0]), "BG": json.dumps(colors[1]), "ACCENT": json.dumps(colors[2])}.items():
            qml = qml.replace("@" + token + "@", str(value))
        (stage / "shell.qml").write_text(qml)
        for name in ("home", "runtime", "config", "cache", "state"):
            (stage / name).mkdir(mode=0o700)
        env = os.environ | {
            "HOME": str(stage / "home"),
            "XDG_RUNTIME_DIR": str(stage / "runtime"),
            "XDG_CONFIG_HOME": str(stage / "config"),
            "XDG_CACHE_HOME": str(stage / "cache"),
            "XDG_STATE_HOME": str(stage / "state"),
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QPA_PLATFORMTHEME": "",
            "QT_STYLE_OVERRIDE": "Basic",
        }
        for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
            env.pop(name, None)
        result = subprocess.run(["dbus-run-session", "--config-file", str(REPO / "tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(stage), "--no-color"], env=env, capture_output=True, text=True, timeout=45)
        logs = result.stdout + result.stderr
        (output_dir / "interaction.log").write_text(logs)
        match = re.search(r"UI_REVIEW_RESULT (\{[^\n]+\})", logs)
        totals = json.loads(match.group(1)) if match else {"passed": 0, "failed": 1}
        totals["returncode"] = result.returncode
        (output_dir / "result.json").write_text(json.dumps(totals, indent=2) + "\n")
        print(variant, json.dumps(totals), flush=True)
        expected = len(re.findall(r"function test_", QML)) + 1
        return totals["passed"] == expected and totals["failed"] == 0 and result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=("normal", "compact", "compact150", "scale125", "scale150", "light", "all"), default="normal")
    parser.add_argument("--output", type=Path, default=REPO / "docs/redesign-v2-review")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = {source.name: source.read_bytes() for source in sorted(REPO.glob("*.qml"))}
    hashes = {name: hashlib.sha256(contents).hexdigest() for name, contents in sources.items()}
    (args.output / "source-sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
    catalog = (REPO / "stations.json").read_bytes()
    variants = ("normal", "compact", "compact150", "scale125", "scale150", "light") if args.variant == "all" else (args.variant,)
    success = True
    for variant in variants:
        success = run(variant, args.output, sources, catalog) and success
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
