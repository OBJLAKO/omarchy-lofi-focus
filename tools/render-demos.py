from pathlib import Path
import os, shutil, subprocess
repo=Path(__file__).resolve().parents[1]
import tempfile
root=Path(tempfile.mkdtemp(prefix='lofi-demo-'))
for name in ('Commons','Ui'):
 p=root/name
 if not p.exists():p.symlink_to(Path('/usr/share/omarchy/shell')/name)
plugin=root/'Plugin';plugin.mkdir(exist_ok=True)
for p in repo.glob('*.qml'):shutil.copy2(p,plugin/p.name)
shutil.copy2(repo/'stations.json',plugin/'stations.json')
p=plugin/'Panel.qml';p.write_text(p.read_text().replace('KeyboardPanel {','PreviewSurface {'))
(plugin/'PreviewSurface.qml').write_text('''import QtQuick
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
out=repo/'docs';out.mkdir(exist_ok=True)

# Scripted walkthrough: real QML components and fixture state, no network/audio.
for scenario in ('youtube', 'nature'):
 frames=root/scenario;frames.mkdir()
 qml = r'''import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "Plugin" as Lofi
Window {
 id: win; width: 468; height: 860; visible: true; color: Color.background
 property int frame: 0
 property bool capturing: false
 property string caption: "@SCENARIO@" === "youtube" ? "01  Open YouTube → Add link" : "01  Pick a station. Make it your space."
 Rectangle {
  id: scene; anchors.fill: parent; color: Color.background
  Rectangle { x:24; y:20; width:420; height:44; color:Qt.alpha(Color.accent,0.12)
   Text { anchors.centerIn:parent; text:win.caption; color:Color.foreground; font.family:Style.font.family; font.pixelSize:12 }
  }
  Lofi.Panel {
   id: player; x:24; y:84; width:420; height:740
   libraryOpen: "@SCENARIO@" === "youtube"
   Component.onCompleted: {
    applyStatus(JSON.stringify({running:true,paused:false,main_running:true,main_state:"playing",station:"lofi-lilo",name:"Lilo-Fi Radio",category:"lofi",category_name:"Lo-fi radio",main_volume:65,master_volume:80,mix:false,youtube_available:true,youtube_entries:[],nature_layers:[],animations:true}))
    open()
   }
  }
  Text { anchors.bottom:parent.bottom; anchors.bottomMargin:10; anchors.horizontalCenter:parent.horizontalCenter; text:"LOFI FOCUS v2  ·  Scripted interface demo"; color:Qt.alpha(Color.foreground,0.55); font.family:Style.font.family; font.pixelSize:10 }
 }
 Timer {
  interval:125; running:true; repeat:true
  onTriggered: {
   if(win.capturing) return
   var f=win.frame
   if ("@SCENARIO@" === "youtube") {
    if(f===16) {win.caption="02  Paste a video. Give it a name."; player.youtubeUrl.text="https://youtu.be/jNQXAC9IVRw";player.youtubeTitle.text="A conversation for a rainy day"}
    if(f===40) {win.caption="03  Save it to your listening shelf";player.youtubeEntries=[{id:"youtube-demo", name:"A conversation for a rainy day", position:0}];player.youtubeUrl.text="";player.youtubeTitle.text=""}
    if(f===64) {win.caption="04  Play audio. Keep your rain.";player.playerStationId="youtube-demo";player.playerName="A conversation for a rainy day";player.mainTitle=player.playerName;player.playerCategory="youtube";player.playerCategoryName="YouTube";player.mainDuration=3840;player.mainPosition=1240;player.natureLayers=[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:30}]}
    if(f===88) {win.caption="05  Seek. Pause. Continue later.";player.mainPosition=1255}
    if(f===108) player.playerPaused=true
   } else {
    if(f===16) player.toggleCollapsed("stations")
    if(f===24) {win.caption="02  Layer in a little rain";player.natureLayers=[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:30}]}
    if(f===48) {win.caption="03  Add a fireplace to the mix";player.natureLayers=[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:30},{id:"noise-fireplace",name:"Fireplace",enabled:true,running:true,volume:20}]}
    if(f===64) {win.caption="04  Balance each sound independently";player.setVolume("noise-rain",45)}
    if(f===80) {win.caption="05  Fold sections. Keep the controls.";player.toggleCollapsed("nature")}
    if(f===96) player.toggleCollapsed("nature")
    if(f===104) {win.caption="06  Master adjusts your entire mix";player.masterVolume=50}
   }
   win.capturing=true
   scene.grabToImage(function(result){result.saveToFile("@FRAMES@/"+String(win.frame).padStart(3,"0")+".png");win.frame++;win.capturing=false;if(win.frame>=128)Qt.quit()})
  }
 }
}
'''
 (root/'shell.qml').write_text(qml.replace('@SCENARIO@',scenario).replace('@FRAMES@',str(frames)))
 env=os.environ|{'QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'','QT_STYLE_OVERRIDE':'Basic','XDG_RUNTIME_DIR':str(root/'runtime')}
 (root/'runtime').mkdir(exist_ok=True,mode=0o700)
 env.pop('WAYLAND_DISPLAY',None)
 subprocess.run(['dbus-run-session','--config-file',str(repo/'tests/dbus-no-activation.conf'),'--','quickshell','-p',str(root),'--no-color'],env=env,check=True,timeout=45)
 subprocess.run(['ffmpeg','-y','-loglevel','error','-framerate','8','-i',str(frames/'%03d.png'),'-filter_complex','split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer',str(out/(scenario+'-guide.gif'))],check=True)
 shutil.copy2(frames/'080.png',out/(scenario+'-demo.png'))
print('Demo frames:',root)
