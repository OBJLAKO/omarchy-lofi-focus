#!/usr/bin/env python3
"""Exercise real Qt slider drag events inside an isolated scrolling page."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
with tempfile.TemporaryDirectory(prefix="skylofi-slider-interaction-") as directory:
    stage = Path(directory)
    for name in ("Commons", "Ui"):
        (stage / name).symlink_to(shell / name, target_is_directory=True)
    (stage / "SkylofiSlider.qml").symlink_to(REPO / "SkylofiSlider.qml")
    (stage / "shell.qml").write_text((REPO / "tests/SliderInteractionTest.qml").read_text())
    for folder in ("home", "runtime", "config", "cache", "state"):
        (stage / folder).mkdir(mode=0o700)
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
    for variable in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
        env.pop(variable, None)
    result = subprocess.run(
        ["dbus-run-session", "--config-file", str(REPO / "tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(stage), "--no-color"],
        env=env, capture_output=True, text=True, timeout=30,
    )
    output = result.stdout + result.stderr
    match = re.search(r"SLIDER_INTERACTION_RESULT (\{[^\n]+\})", output)
    if result.returncode or not match or json.loads(match.group(1)) != {"passed": 6, "failed": 0}:
        raise SystemExit(output or "Slider interaction tests did not report results")
    print("5 slider interaction tests passed")
