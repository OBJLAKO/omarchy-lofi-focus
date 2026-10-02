#!/usr/bin/env python3
"""Exercise actual bar status/motion bindings without starting audio or Rust."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="skylofi-bar-motion-") as directory:
    stage=Path(directory)
    for name in ("Commons","Ui"):
        (stage/name).symlink_to(Path("/usr/share/omarchy/shell")/name)
    plugin=stage/"Plugin"
    plugin.mkdir()
    for name in ("BarWidget.qml","PlaybackWave.qml"):
        shutil.copy2(repo/name,plugin/name)
    bar=plugin/"BarWidget.qml"
    bar.write_text(bar.read_text().replace("Component.onCompleted: backend.running = true","Component.onCompleted: backend.running = false")
                   .replace("id: panelLoader\n    active: true","id: panelLoader\n    active: false"))
    (stage/"shell.qml").write_text((repo/"tests/BarMotionTest.qml").read_text())
    runtime=stage/"runtime"
    runtime.mkdir(mode=0o700)
    env=os.environ|{"QT_QPA_PLATFORM":"offscreen","QT_QPA_PLATFORMTHEME":"","QT_STYLE_OVERRIDE":"Basic",
                    "XDG_RUNTIME_DIR":str(runtime),"XDG_CONFIG_HOME":str(stage/"config"),
                    "XDG_STATE_HOME":str(stage/"state"),"XDG_CACHE_HOME":str(stage/"cache")}
    env.pop("WAYLAND_DISPLAY",None)
    result=subprocess.run(["dbus-run-session","--config-file",str(repo/"tests/dbus-no-activation.conf"),"--",
                           "quickshell","-p",str(stage),"--no-color"],env=env,capture_output=True,text=True,timeout=25)
    output=result.stdout+result.stderr
    match=re.search(r"BAR_MOTION_TEST_RESULT (\{[^\n]+\})",output)
    if not match or result.returncode or json.loads(match.group(1)) != {"passed":8,"failed":0} or "ERROR" in output:
        raise SystemExit(output or "Bar motion tests did not report results")
    print("7 actual bar status, ongoing motion and visibility tests passed")
