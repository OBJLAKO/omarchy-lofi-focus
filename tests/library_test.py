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
with tempfile.TemporaryDirectory(prefix="lofi-library-test-") as directory:
    test = Path(directory)
    for name in ("Commons", "Ui"):
        (test / name).symlink_to(shell / name, target_is_directory=True)
    (test / "Plugin").symlink_to(repo, target_is_directory=True)
    (test / "shell.qml").write_text((repo / "tests/LibraryTest.qml").read_text())
    runtime = test / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ | {
        "XDG_RUNTIME_DIR": str(runtime),
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QPA_PLATFORMTHEME": "",
        "QT_STYLE_OVERRIDE": "Basic",
    }
    env.pop("WAYLAND_DISPLAY", None)
    # Keep this temporary shell off the user's session bus as well as offscreen.
    result = subprocess.run(
        ["dbus-run-session", "--config-file", str(repo / "tests/dbus-no-activation.conf"), "--", "quickshell", "-p", str(test), "--no-color"],
        env=env, capture_output=True, text=True, timeout=30,
    )
    output = result.stdout + result.stderr
    match = re.search(r"LIBRARY_TEST_RESULT (\{[^\n]+\})", output)
    if not match:
        raise SystemExit(output or "Library tests did not report results")
    totals = json.loads(match.group(1))
    # Seven tests and initTestCase must finish before cleanupTestCase reports.
    if result.returncode or totals != {"passed": 8, "failed": 0}:
        raise SystemExit(output)
    print("7 library interaction tests passed")
