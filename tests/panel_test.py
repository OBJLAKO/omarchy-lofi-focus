#!/usr/bin/env python3
"""Exercise actual Qt pointer/keyboard events with Omarchy's installed UI types."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
with tempfile.TemporaryDirectory(prefix="lofi-panel-test-") as directory:
    test = Path(directory)
    for name in ("Commons", "Ui"):
        (test / name).symlink_to(shell / name, target_is_directory=True)
    (test / "Plugin").symlink_to(repo, target_is_directory=True)
    (test / "shell.qml").write_text((repo / "tests/PanelTest.qml").read_text())
    runtime = test / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ | {
        "XDG_RUNTIME_DIR": str(runtime),
        "QT_QPA_PLATFORM": "wayland",
        "QT_QPA_PLATFORMTHEME": "",
        "QT_STYLE_OVERRIDE": "Basic",
    }
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
    env["WAYLAND_DISPLAY"] = str(Path(os.environ["XDG_RUNTIME_DIR"])/display)
    # Use the native backend with no visible windows and a private session bus.
    result = subprocess.run(
        ["dbus-run-session", "--config-file", str(repo / "tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(test), "--no-color"],
        env=env, capture_output=True, text=True, timeout=30,
    )
    output = result.stdout + result.stderr
    match = re.search(r"PANEL_TEST_RESULT (\{[^\n]+\})", output)
    if not match:
        raise SystemExit(output or "Panel tests did not report results")
    totals = json.loads(match.group(1))
    # Nine tests and initTestCase must finish before cleanupTestCase reports.
    if result.returncode or totals != {"passed": 10, "failed": 0}:
        raise SystemExit(output)
    print("9 panel state tests passed")
