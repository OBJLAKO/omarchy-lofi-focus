#!/usr/bin/env python3
"""Exercise ongoing playback motion in isolated offscreen Qt, without audio."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="skylofi-playback-motion-") as directory:
    stage = Path(directory)
    plugin = stage / "Plugin"
    plugin.mkdir()
    shutil.copy2(repo / "PlaybackWave.qml", plugin / "PlaybackWave.qml")
    shutil.copy2(repo / "tests" / "PlaybackWaveTest.qml", stage / "shell.qml")
    runtime = stage / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ | {
        "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
        "QT_STYLE_OVERRIDE": "Basic", "XDG_RUNTIME_DIR": str(runtime),
        "XDG_CONFIG_HOME": str(stage / "config"), "XDG_STATE_HOME": str(stage / "state"),
        "XDG_CACHE_HOME": str(stage / "cache"),
    }
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run([
        "dbus-run-session", "--config-file", str(repo / "tests" / "dbus-no-activation.conf"),
        "--", "quickshell", "-p", str(stage), "--no-color",
    ], env=env, capture_output=True, text=True, timeout=25)
    output = result.stdout + result.stderr
    match = re.search(r"PLAYBACK_MOTION_TEST_RESULT (\{[^\n]+\})", output)
    if not match or result.returncode or json.loads(match.group(1)) != {"passed": 7, "failed": 0} or "ERROR" in output:
        raise SystemExit(output or "Playback motion tests did not report results")
    print("6 ongoing playback motion state and update-budget tests passed")
