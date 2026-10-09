#!/usr/bin/env python3
"""Real QML task completion and failed-import recovery, without live playback."""
import importlib.util
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ui_review", repo / "tools/ui_review_v2.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)
qml = (repo / "tests/UsabilityTest.qml").read_text()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--profile", choices=("normal", "compact150", "light"), default="normal")
args = parser.parse_args()
if args.profile == "compact150":
    qml = qml.replace("width: 480; height: 620", "width: 430; height: 480")
    qml = qml.replace("Style.fontBaseSize = 12", "Style.fontBaseSize = 18")
if args.profile == "light":
    qml = qml.replace("Style.spacingScale = 1", 'Style.spacingScale = 1\n      Color.foreground = "#24282d"; Color.background = "#f6f7f8"; Color.accent = "#326d9b"')
expected = len(re.findall(r"function test_", qml)) + 1
with tempfile.TemporaryDirectory(prefix="skylofi-usability-") as directory:
    stage = Path(directory)
    for name in ("Commons", "Ui"):
        (stage / name).symlink_to(Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell" / name)
    plugin = stage / "Plugin"
    plugin.mkdir()
    for source in repo.glob("*.qml"):
        (plugin / source.name).write_bytes(source.read_bytes())
    (plugin / "stations.json").write_bytes((repo / "stations.json").read_bytes())
    panel = plugin / "Panel.qml"
    panel.write_text(panel.read_text().replace("KeyboardPanel {", "PreviewSurface {"))
    (plugin / "PreviewSurface.qml").write_text(review.SURFACE)
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
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    for name in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
        env.pop(name, None)
    result = subprocess.run(
        ["dbus-run-session", "--config-file", str(repo / "tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(stage), "--no-color"],
        env=env, capture_output=True, text=True, timeout=45,
    )
    output = result.stdout + result.stderr
    match = re.search(r"USABILITY_TEST_RESULT (\{[^\n]+\})", output)
    totals = json.loads(match.group(1)) if match else None
    if result.returncode or totals != {"passed": expected, "failed": 0}:
        raise SystemExit(output or "Usability tests did not report results")
    print(f"{expected - 1} rendered usability and import-recovery regressions passed ({args.profile})")
