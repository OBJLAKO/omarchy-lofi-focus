#!/usr/bin/env python3
"""Record actual QML controls with deterministic, isolated sample playback state.

No decoder, installed settings, personal library or network access is used.
This demonstrates interaction and motion, not connection or playback latency.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

import ui_review_v2 as review

REPO = Path(__file__).resolve().parents[1]
MOVIE = r'''
  property string caption: ""
  Text { x: 24; y: 13; text: "Skylofi 3 · @TITLE@"; color: Color.foreground; font.pixelSize: 23; font.weight: Font.DemiBold }
  Text { x: 24; y: 48; text: win.caption; color: "#a2b0ba"; font.pixelSize: 15 }
  TestCase {
    id: movie; name: "SkylofiShowcase"; when: win.visible
    property bool captured: false
    property int frame: 0
    property var demo: ({running:true,paused:false,main_running:true,main_state:"playing",source_kind:"radio",station:"lofi-lilo",name:"Lilo-Fi Radio",category:"lofi",category_name:"Lo-fi radio",main_volume:65,master_volume:80,mix:true,bg_station:"voice-changelog",bg_name:"The Changelog",bg_running:true,bg_state:"playing",bg_volume:30,youtube_available:true,youtube_entries:[{id:"youtube-demo",name:"Sunday morning jazz",is_live:false,position:0},{id:"youtube-demo2",name:"A conversation for a rainy day",is_live:false,position:1240}],nature_layers:[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:35},{id:"noise-fireplace",name:"Fireplace",enabled:true,running:true,volume:20}],animations:true,equalizer:true,fade_enabled:true,fade_seconds:3,ducking:true,duck_level:35})
    function item(name) { var found=findChild(panel,name); verify(found!==null,"Missing control "+name); return found }
    function publish() { host.statusJson=JSON.stringify(demo); panel.applyStatus(host.statusJson) }
    function perform(args) {
      if(args[0]==="toggle") demo.paused=!demo.paused
      else if(args[0]==="start") {
        demo.station=args[1]; demo.paused=false; demo.running=true; demo.main_running=true; demo.main_state="playing"
        if(args[1].indexOf("youtube-")===0) { demo.name="Sunday morning jazz"; demo.source_kind="recording"; demo.category="youtube"; demo.category_name="YouTube"; demo.main_title=demo.name; demo.main_position=420; demo.main_duration=3600; demo.can_seek=true; demo.bg_running=false; demo.bg_state="off" }
        else { demo.name=args[1]==="lofi-purrple-cat" ? "Purrple Cat" : "Lilo-Fi Radio"; demo.source_kind="radio"; demo.category="lofi"; demo.category_name="Lo-fi radio"; demo.main_duration=0; demo.can_seek=false; demo.bg_running=true; demo.bg_state="playing" }
      } else if(args[0]==="vol") {
        var value=Number(args[2]); if(args[1]==="main") demo.main_volume=value; else if(args[1]==="master") demo.master_volume=value; else if(args[1]==="bg") demo.bg_volume=value
        else for(var layer of demo.nature_layers) if(layer.id===args[1]) layer.volume=value
      } else if(args[0]==="seek") demo.main_position=Number(args[1])
      else if(args[0]==="nature") demo.nature_layers=demo.nature_layers.concat([{id:args[1],name:"Ocean waves",enabled:true,running:true,volume:25}])
      else if(args[0]==="ducking") demo.ducking=args[1]==="on"
      else if(args[0]==="ui") {
        var fields={fade:"fade_enabled",fadeSeconds:"fade_seconds",duckLevel:"duck_level",animations:"animations",equalizer:"equalizer_animation"}
        demo[fields[args[1]]]=["fadeSeconds","duckLevel"].indexOf(args[1])>=0 ? Number(args[2]) : args[2]==="on"
      }
      publish()
    }
    function photograph() {
      var start=Date.now(); captured=false
      var number=String(frame++).padStart(4,"0")
      win.contentItem.grabToImage(function(result){ captured=result.saveToFile("@OUT@/frame_"+number+".png") })
      var end=Date.now()+2000; while(!captured && Date.now()<end) wait(2)
      verify(captured,"Frame capture failed")
      wait(Math.max(1,50-(Date.now()-start)))
    }
    function hold(seconds) { for(var n=0;n<Math.round(seconds*20);n++) photograph() }
    function click(name) {var c=item(name); mouseMove(c,c.width/2,c.height/2); hold(0.15); mouseClick(c,c.width/2,c.height/2)}
    function withProperty(parent,property) {
      if(parent[property]!==undefined) return parent
      if(parent.children) for(var child of parent.children) {var found=withProperty(child,property); if(found)return found}
      return null
    }
    function slider(name) {var c=withProperty(item(name),"liveValue"); verify(c!==null,"Slider missing "+name); return c}
    function drag(name,from,to) {
      var c=slider(name); c.forceActiveFocus(); mousePress(c,c.width*from,c.height/2)
      for(var n=0;n<18;n++){mouseMove(c,c.width*(from+(to-from)*n/17),c.height/2); photograph()}
      mouseRelease(c,c.width*to,c.height/2); hold(0.5)
    }
    function toggle(name) {var c=findChild(item(name),"settingSwitch"); verify(c!==null,"Switch missing "+name);mouseMove(c,c.width/2,c.height/2);hold(0.15);mouseClick(c,c.width/2,c.height/2)}
    function typeText(text) {for(var character of text) {keyClick(character); hold(0.1)}}
    function scrollTo(name,control) {panel.ensureVisible(item(name),item(control)); waitForPolish(win); wait(100)}
    function initTestCase() {
      Style.fontBaseSize=15; Style.spacingScale=1; Style.spacingScaleWithFont=true; Style.cornerRadius=6
      Color.foreground="#d8dde1"; Color.background="#14191e"; Color.accent="#86b4d3"; Color.urgent="#c65c5c"
      wait(150); publish(); panel.open(); panel.showView(@VIEW@); waitForPolish(win); wait(250)
    }
    function test_record() {
      @STEPS@
      console.log("SHOWCASE_RESULT",JSON.stringify({frames:frame,commands:host.commands.length,failed:qtest_results.failCount}))
    }
  }
}
'''

CLIPS = {
    "listen": ("Listen", 0, r'''
      win.caption="Choose a radio station. Keep your saved links nearby."; hold(1)
      click("station-lofi-purrple-cat"); hold(1.2)
      click("togglePlayback"); hold(0.8); click("togglePlayback"); hold(1)
      click("savedSourceTab"); hold(1.1)
      click("libraryEntry-youtube-demo"); hold(1.4)
      var progress=item("playbackProgress"); progress.forceActiveFocus(); keyClick(Qt.Key_Right); hold(0.8)
      click("radioSourceTab"); click("station-lofi-lilo"); hold(1)
    '''),
    "mix": ("Mix", 1, r'''
      win.caption="Balance music, voices and nature independently."; hold(1)
      drag("soundtrackLevel",0.65,0.42)
      drag("natureLevel-noise-rain",0.35,0.55)
      scrollTo("mixScroll","naturePicker"); click("naturePicker"); hold(0.8)
      var search=findChild(item("naturePicker"),"focusDropdownSearch"); tryCompare(search,"activeFocus",true); typeText("ocean"); hold(0.7)
      keyClick(Qt.Key_Return); hold(0.7)
      scrollTo("mixScroll","natureLevel-noise-waves"); hold(1)
      item("mixScroll").contentY=0; hold(0.5)
      drag("allSoundsLevel",0.8,0.65); hold(1)
    '''),
    "settings": ("Settings", 2, r'''
      win.caption="Set gentle fades, dictation ducking and quiet motion."; hold(1)
      drag("fadeDuration",0.3,0.6)
      toggle("dictationToggle"); hold(0.7); toggle("dictationToggle"); hold(0.7)
      scrollTo("settingsScroll","dictationVolume"); drag("dictationVolume",0.35,0.5)
      scrollTo("settingsScroll","playbackIndicatorToggle"); hold(0.8)
      toggle("animationsToggle"); hold(1); toggle("animationsToggle"); hold(1.2)
      item("settingsScroll").contentY=0; hold(1)
    '''),
}


def capture(name, output, frames_root):
    title, view, steps = CLIPS[name]
    frames = frames_root / name
    frames.mkdir(parents=True, exist_ok=True)
    for previous in frames.glob("frame_[0-9][0-9][0-9][0-9].png"):
        previous.unlink()
    sources = {source.name: source.read_bytes() for source in sorted(REPO.glob("*.qml"))}
    with tempfile.TemporaryDirectory(prefix="skylofi-showcase-") as directory:
        stage = Path(directory)
        for shared in ("Commons", "Ui"):
            (stage / shared).symlink_to(Path("/usr/share/omarchy/shell") / shared)
        plugin = stage / "Plugin"
        plugin.mkdir()
        for filename, contents in sources.items():
            (plugin / filename).write_bytes(contents)
        (plugin / "stations.json").write_bytes((REPO / "stations.json").read_bytes())
        panel = plugin / "Panel.qml"
        panel.write_text(panel.read_text().replace("KeyboardPanel {", "PreviewSurface {"))
        surface = review.SURFACE.replace("y: (parent.height-height)/2", "y: 80")
        (plugin / "PreviewSurface.qml").write_text(surface)
        prefix = review.QML.split("  TestCase {")[0].replace("commands=commands.concat([args])", "commands=commands.concat([args]); movie.perform(args)")
        qml = prefix + MOVIE
        for token, value in {"WIDTH":620,"HEIGHT":860,"TITLE":title,"VIEW":view,"OUT":str(frames),"STEPS":steps}.items():
            qml = qml.replace("@" + token + "@", str(value))
        (stage / "shell.qml").write_text(qml)
        for folder in ("home", "runtime", "config", "cache", "state"):
            (stage / folder).mkdir(mode=0o700)
        env = os.environ | {"HOME":str(stage/"home"),"XDG_RUNTIME_DIR":str(stage/"runtime"),"XDG_CONFIG_HOME":str(stage/"config"),"XDG_CACHE_HOME":str(stage/"cache"),"XDG_STATE_HOME":str(stage/"state"),"QT_QPA_PLATFORM":"offscreen","QT_QPA_PLATFORMTHEME":"","QT_STYLE_OVERRIDE":"Basic"}
        for variable in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
            env.pop(variable, None)
        result = subprocess.run(["dbus-run-session", "--config-file", str(REPO/"tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(stage), "--no-color"], env=env, capture_output=True, text=True, timeout=80)
        logs = result.stdout + result.stderr
        (frames / "capture.log").write_text(logs)
        match = re.search(r"SHOWCASE_RESULT (\{[^\n]+\})", logs)
        totals = json.loads(match.group(1)) if match else {"failed":1}
        if result.returncode or totals["failed"]:
            raise RuntimeError(f"{name} capture failed (exit {result.returncode}, {totals}): {logs[-6000:]}")
        target = output / f"{name}-demo.gif"
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "20", "-i", str(frames/"frame_%04d.png"), "-filter_complex", "[0:v]split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3", "-loop", "0", str(target)], check=True, timeout=90)
        return {"file":target.name,"width":620,"height":860,"fps":20,"frames":totals["frames"],"commands":totals["commands"],"bytes":target.stat().st_size,"sha256":hashlib.sha256(target.read_bytes()).hexdigest(),"source_sha256":{filename:hashlib.sha256(contents).hexdigest() for filename, contents in sources.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", choices=(*CLIPS, "all"), default="all")
    parser.add_argument("--output", type=Path, default=REPO/"docs/showcase")
    parser.add_argument("--frames", type=Path, default=Path("/tmp/skylofi-showcase-frames"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    clips = CLIPS if args.clip=="all" else (args.clip,)
    manifest_path = output / "capture-manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"scope":"Actual QML controls, isolated sample state; no live/network playback or latency claim.","clips":{}}
    for name in clips:
        manifest["clips"][name]=capture(name, output, args.frames.resolve())
        manifest_path.write_text(json.dumps(manifest, indent=2)+"\n")
        print(name, json.dumps({key:value for key,value in manifest["clips"][name].items() if key!="source_sha256"}), flush=True)


if __name__=="__main__":
    main()
