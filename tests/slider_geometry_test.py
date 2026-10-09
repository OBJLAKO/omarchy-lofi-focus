#!/usr/bin/env python3
"""Verify rendered focus/neighbor bounds with real Qt controls and isolated state."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from tools.ui_review_v2 import SURFACE

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output",type=Path,help="Optional directory for focused real-QML screenshots")
arguments = parser.parse_args()
sources = {path.name: path.read_bytes() for path in REPO.glob("*.qml")}
catalog = (REPO / "stations.json").read_bytes()
fixture = (REPO / "tests/SliderGeometryTest.qml").read_text()
for name, font, width, height in (("normal",12,480,620),("scale125",15,595,770),("scale150",18,710,920),("compact150",18,430,480)):
    destination = arguments.output.resolve() / name if arguments.output else None
    if destination:
        destination.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="skylofi-slider-geometry-") as directory:
        stage = Path(directory)
        for module in ("Commons", "Ui"):
            (stage / module).symlink_to(Path("/usr/share/omarchy/shell") / module)
        plugin = stage / "Plugin"
        plugin.mkdir()
        for filename, content in sources.items():
            (plugin / filename).write_bytes(content)
        panel = plugin / "Panel.qml"
        panel.write_text(panel.read_text().replace("KeyboardPanel {", "PreviewSurface {"))
        (plugin / "PreviewSurface.qml").write_text(SURFACE)
        (plugin / "stations.json").write_bytes(catalog)
        qml = fixture.replace("@FONT@",str(font)).replace("@WIDTH@",str(width)).replace("@HEIGHT@",str(height)).replace("@OUT@",str(destination) if destination else "")
        (stage / "shell.qml").write_text(qml)
        for folder in ("home","runtime","config","cache","state"):
            (stage / folder).mkdir(mode=0o700)
        env = os.environ | {"HOME":str(stage / "home"),"XDG_RUNTIME_DIR":str(stage / "runtime"),"XDG_CONFIG_HOME":str(stage / "config"),"XDG_CACHE_HOME":str(stage / "cache"),"XDG_STATE_HOME":str(stage / "state"),"QT_QPA_PLATFORM":"offscreen","QT_QPA_PLATFORMTHEME":"","QT_STYLE_OVERRIDE":"Basic"}
        for variable in ("WAYLAND_DISPLAY","DISPLAY","HYPRLAND_INSTANCE_SIGNATURE","DBUS_SESSION_BUS_ADDRESS"):
            env.pop(variable,None)
        result = subprocess.run(["dbus-run-session","--config-file",str(REPO / "tests/dbus-no-activation.conf"),"--","quickshell","-p",str(stage),"--no-color"],env=env,capture_output=True,text=True,timeout=30)
        output = result.stdout + result.stderr
        match = re.search(r"SLIDER_GEOMETRY_RESULT (\{[^\n]+\})",output)
        totals = json.loads(match.group(1)) if match else None
        if result.returncode or totals != {"passed":9,"failed":0}:
            raise SystemExit(f"{name}: {output}")
        print(f"{name}: 8 rendered focus/neighbor/endpoint checks passed",flush=True)
