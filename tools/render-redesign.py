#!/usr/bin/env python3
"""Render the actual QML redesign with fixture data, without audio/network.

Uses installed Omarchy UI types on a private bus without activation paths.
The temporary PreviewSurface replaces only layer-shell window plumbing.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
out = repo / "docs" / "redesign"
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="skylofi-design-") as directory:
    stage = Path(directory)
    for name in ("Commons", "Ui"):
        (stage / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
    plugin = stage / "Plugin"
    plugin.mkdir()
    for source in repo.glob("*.qml"):
        shutil.copy2(source, plugin / source.name)
    shutil.copy2(repo / "stations.json", plugin / "stations.json")
    panel = plugin / "Panel.qml"
    panel.write_text(panel.read_text().replace("KeyboardPanel {", "PreviewSurface {"))
    (plugin / "PreviewSurface.qml").write_text('''import QtQuick
Item {
 property var anchorItem
 property var owner
 property var bar
 property bool open
 property bool centerOnBar
 property var focusTarget
 property real contentWidth
 property real contentHeight
 width: parent.width
 height: parent.height
 function fittedContentWidth(value) { return value }
 function fittedContentHeight(value) { return value }
}
''')
    qml = r'''import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "Plugin" as Lofi
Window {
 id: win; width: 478; height: 696; visible: true; color: Color.background
 property int scenario: 0
 function findItem(item, name) {
  if (item.objectName === name) return item
  if (!item.children) return null
  for (var i=0;i<item.children.length;i++) { var found=findItem(item.children[i], name); if(found) return found }
  return null
 }
 Rectangle {
  id: scene; anchors.fill: parent; color: Color.background
  BorderSurface {
   x: 10; y: 10; width: 458; height: 676
   color: Color.popups.background
   borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
   radius: Style.cornerRadius
   Lofi.Panel {
    id: player; x: 14; y: 16; width: 430; height: 644
    Component.onCompleted: {
     applyStatus(JSON.stringify({running:true,paused:false,main_running:true,main_state:"playing",station:"lofi-lilo",name:"Lilo-Fi Radio",category:"lofi",category_name:"Lo-fi radio",main_volume:65,master_volume:80,mix:true,bg_station:"voice-changelog",bg_name:"The Changelog",bg_volume:30,youtube_available:true,youtube_entries:[{id:"youtube-demo",name:"A conversation for a rainy day",position:1240},{id:"youtube-demo2",name:"Sunday morning jazz",position:0}],nature_layers:[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:35},{id:"noise-fireplace",name:"Fireplace",enabled:true,running:true,volume:20}],animations:false,fade_enabled:true,fade_seconds:3,ducking:true,duck_level:35}))
     open()
    }
   }
  }
 }
 Timer {
  interval: 500; running: true; repeat: true
  onTriggered: {
   var names = ["listen", "mix", "settings", "links", "add-link", "library-search", "remove-link"]
   scene.grabToImage(function(result) {
    result.saveToFile("@OUT@/" + names[win.scenario] + ".png")
    win.scenario++
    if(win.scenario === 1) player.showView(1)
    else if(win.scenario === 2) player.showView(2)
    else if(win.scenario === 3) { player.showView(0); player.libraryOpen=true; player.playerStationId="youtube-demo";player.playerName="A conversation for a rainy day";player.mainTitle=player.playerName;player.playerCategory="youtube";player.playerCategoryName="YouTube";player.mainDuration=3840;player.mainPosition=1240 }
    else if(win.scenario === 4) { var lib=win.findItem(player,"youtubeLibrary");lib.addingLink=true;player.youtubeUrl.text="https://youtu.be/jNQXAC9IVRw";player.youtubeTitle.text="Rainy day conversation" }
    else if(win.scenario === 5) { var lib=win.findItem(player,"youtubeLibrary");lib.addingLink=false;player.youtubeEntries=[{id:"youtube-demo",name:"A conversation for a rainy day",position:1240},{id:"youtube-demo2",name:"Sunday morning jazz",position:0},{id:"youtube-demo3",name:"Forest piano",position:0},{id:"youtube-demo4",name:"After hours jazz",position:500},{id:"youtube-demo5",name:"Quiet coding",position:0}];win.findItem(player,"librarySearch").text="jazz" }
    else if(win.scenario === 6) { win.findItem(player,"librarySearch").text="";player.youtubeEntries=[{id:"youtube-demo",name:"A conversation for a rainy day",position:1240},{id:"youtube-demo2",name:"Sunday morning jazz",position:0}];win.findItem(player,"youtubeLibrary").pendingRemoval="youtube-demo" }
    else Qt.quit()
   })
  }
 }
}
'''
    (stage / "shell.qml").write_text(qml.replace("@OUT@", str(out)))
    runtime = stage / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ | {"QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "", "QT_STYLE_OVERRIDE": "Basic", "XDG_RUNTIME_DIR": str(runtime)}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["dbus-run-session", "--config-file", str(repo / "tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(stage), "--no-color"], env=env, capture_output=True, text=True, timeout=20)
    if result.returncode or "ERROR" in result.stdout + result.stderr:
        raise SystemExit(result.stdout + result.stderr)
print(out)
