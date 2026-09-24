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
with tempfile.TemporaryDirectory(prefix="lofi-dropdown-test-") as directory:
    test = Path(directory)
    for name in ("Commons", "Ui"):
        (test / name).symlink_to(shell / name, target_is_directory=True)
    (test / "FocusDropdown.qml").symlink_to(repo / "FocusDropdown.qml")
    (test / "shell.qml").write_text((repo / "tests/DropdownTest.qml").read_text())
    runtime = test / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ | {
        "XDG_RUNTIME_DIR": str(runtime),
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QPA_PLATFORMTHEME": "",
        "QT_STYLE_OVERRIDE": "Basic",
    }
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(
        ["quickshell", "-p", str(test), "--no-color"],
        env=env, capture_output=True, text=True, timeout=30,
    )
    output = result.stdout + result.stderr
    match = re.search(r"DROPDOWN_TEST_RESULT (\{[^\n]+\})", output)
    if not match:
        raise SystemExit(output or "Dropdown tests did not report results")
    totals = json.loads(match.group(1))
    # Five tests and initTestCase must finish before cleanupTestCase reports.
    if result.returncode or totals != {"passed": 6, "failed": 0}:
        raise SystemExit(output)
    print("5 dropdown interaction tests passed")
