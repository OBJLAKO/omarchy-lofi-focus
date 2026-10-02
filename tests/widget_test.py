#!/usr/bin/env python3
"""Exercise the real Rust Process/stdin/stdout QML transport on an isolated bus.

Set SKYLOFI_NATIVE to a built release executable. No audio is started and the
installed plugin/settings are never touched. Shutdown runs on the same private
bus before its temporary runtime disappears.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
if len(sys.argv) > 1 and sys.argv[1] == "--inside":
    stage = Path(sys.argv[2])
    try:
        result = subprocess.run(["quickshell", "-p", str(stage), "--no-color"], capture_output=True, text=True, timeout=25)
        output = result.stdout + result.stderr
    finally:
        subprocess.run([str(stage / "Plugin" / "lofi-player"), "shutdown"], capture_output=True, timeout=10)
    match = re.search(r"WIDGET_TEST_RESULT (\{[^\n]+\})", output)
    if not match or result.returncode or json.loads(match.group(1)) != {"passed": 4, "failed": 0} or "ERROR" in output:
        raise SystemExit(output or "Widget tests did not report results")
    print("3 real Rust/QML transport tests passed")
    raise SystemExit(0)

native = Path(os.environ.get("SKYLOFI_NATIVE", ""))
if not native.is_file() or not os.access(native, os.X_OK):
    raise SystemExit("Set SKYLOFI_NATIVE to the built native release executable")
with tempfile.TemporaryDirectory(prefix="skylofi-widget-") as directory:
    stage = Path(directory)
    for name in ("Commons", "Ui"):
        (stage / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
    plugin = stage / "Plugin"
    plugin.mkdir()
    for source in repo.glob("*.qml"):
        shutil.copy2(source, plugin / source.name)
    for name in ("stations.json", "lofi-player"):
        shutil.copy2(repo / name, plugin / name)
    (stage / "shell.qml").write_text((repo / "tests" / "WidgetTest.qml").read_text())
    runtime = stage / "runtime"
    runtime.mkdir(mode=0o700)
    env = os.environ | {"SKYLOFI_NATIVE": str(native.resolve()), "LOFI_BACKEND": "rust", "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "", "QT_STYLE_OVERRIDE": "Basic", "XDG_RUNTIME_DIR": str(runtime), "XDG_STATE_HOME": str(stage / "state"), "XDG_CONFIG_HOME": str(stage / "config")}
    env.pop("WAYLAND_DISPLAY", None)
    subprocess.run(["dbus-run-session", "--config-file", str(repo / "tests" / "dbus-no-activation.conf"), "--", sys.executable, "-B", str(Path(__file__).resolve()), "--inside", str(stage)], env=env, check=True, timeout=40)
