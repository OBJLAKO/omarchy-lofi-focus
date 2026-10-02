#!/usr/bin/env python3
"""Measure the incremental cost of ongoing playback motion in actual QML.

The full panel and actual bar widget are frozen into an offscreen fixture.
A tiny fixture-only JSON process replaces audio/Rust transport. Only Quickshell
CPU/PSS is sampled; no GPU/FPS, native controller or desktop-shell claim.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time

from perf_baseline import host_context
from perf_live import snapshot

REPO = Path(__file__).resolve().parents[1]
STATUS = {
    "running": True, "paused": False, "main_running": True,
    "main_state": "playing", "source_kind": "radio", "station": "lofi-lilo",
    "name": "Lilo-Fi Radio", "category": "lofi", "category_name": "Lo-fi radio",
    "main_volume": 65, "master_volume": 80, "mix": False,
    "bg_running": False, "bg_state": "stopped", "bg_volume": 30,
    "youtube_available": True, "youtube_entries": [], "nature_layers": [],
    "animations": True, "equalizer_animation": True, "fade_enabled": True,
    "fade_seconds": 3, "ducking": True, "duck_level": 35,
}
PREVIEW = '''import QtQuick
Item {
 property var anchorItem
 property var owner
 property var bar
 property bool open
 property bool centerOnBar
 property var focusTarget
 property int padding
 property real contentWidth
 property real contentHeight
 width: parent.width
 height: parent.height
 visible: open
 function fittedContentWidth(value) { return value }
 function fittedContentHeight(value) { return value }
}
'''
QML = '''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Plugin" as Lofi
Window {
 id: win
 width: 480; height: 620; visible: @WINDOW_VISIBLE@
 color: Color.background
 Lofi.BarWidget { id: widget; x: 442; y: 0 }
 Lofi.Panel {
  id: player
  x: 32; y: 32; width: 416; height: 556
  hostWidget: widget
  Component.onCompleted: { applyStatus(JSON.stringify(@STATUS@)); @PANEL_ACTION@ }
 }
 function indicators(item, out) {
  if (item.frameCount !== undefined && item.updateInterval !== undefined) {
   out.push({name: item.objectName || "panelPlaybackActivity", moving: item.moving,
    presented: item.presented, frameCount: item.frameCount, interval: item.updateInterval})
  }
  if (!item.children) return
  for(var i=0; i<item.children.length; i++) indicators(item.children[i], out)
 }
 IpcHandler {
  target: "motion_probe"
  function counters(): string { var out=[]; win.indicators(win.contentItem,out); return JSON.stringify(out) }
 }
 Timer { interval: 1000; running: true; onTriggered: console.log("MOTION_PERF_READY") }
}
'''


def counters(pid, env):
    result = subprocess.run(["quickshell", "ipc", "--pid", str(pid), "call", "motion_probe", "counters"],
                            env=env, capture_output=True, text=True, timeout=4, check=True)
    return json.loads(result.stdout.strip())


def measure(frozen, label, panel_open, animate, window_visible, seconds):
    with tempfile.TemporaryDirectory(prefix="skylofi-motion-perf-") as directory:
        stage = Path(directory)
        for name in ("Commons", "Ui"):
            (stage / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
        plugin = stage / "Plugin"
        shutil.copytree(frozen, plugin)
        panel = plugin / "Panel.qml"
        panel.write_text(panel.read_text().replace("KeyboardPanel {", "PreviewSurface {"))
        (plugin / "PreviewSurface.qml").write_text(PREVIEW)
        bar = plugin / "BarWidget.qml"
        # One independently placed real panel is measured; avoid loading a
        # second invisible layer-shell panel through the bar's production loader.
        bar.write_text(bar.read_text().replace("id: panelLoader\n    active: true", "id: panelLoader\n    active: false"))
        # Keep the same finite interface transitions in both cases. Toggle
        # only the ongoing indicator so initial render-cache allocation is
        # not confused with its continuing cost.
        status = STATUS | {"equalizer_animation": animate}
        backend = plugin / "lofi-player"
        backend.write_text("#!/usr/bin/env python3\nimport json,sys\nstate=" + repr(status) +
                           "\nprint(json.dumps({'status':state}),flush=True)\n" +
                           "for line in sys.stdin:\n request=json.loads(line)\n print(json.dumps({'id':request.get('id'),'ok':True,'status':state}),flush=True)\n")
        backend.chmod(0o755)
        (stage / "shell.qml").write_text(QML.replace("@WINDOW_VISIBLE@", str(window_visible).lower())
                                      .replace("@STATUS@", json.dumps(status))
                                      .replace("@PANEL_ACTION@", "open()" if panel_open else "close()"))
        runtime = stage / "runtime"
        runtime.mkdir(mode=0o700)
        env = os.environ | {
            "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "", "QT_STYLE_OVERRIDE": "Basic",
            "XDG_RUNTIME_DIR": str(runtime), "XDG_CONFIG_HOME": str(stage / "config"),
            "XDG_STATE_HOME": str(stage / "state"), "XDG_CACHE_HOME": str(stage / "cache"),
        }
        env.pop("WAYLAND_DISPLAY", None)
        bus = subprocess.Popen(["dbus-daemon", "--config-file=" + str(REPO / "tests/dbus-no-activation.conf"),
                                "--nofork", "--print-address=1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        env["DBUS_SESSION_BUS_ADDRESS"] = bus.stdout.readline().strip()
        log = stage / "quickshell.log"
        try:
            with log.open("w") as output:
                process = subprocess.Popen(["quickshell", "-p", str(stage), "--no-color"], env=env,
                                           stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError(log.read_text())
                    if "MOTION_PERF_READY" in log.read_text():
                        break
                    time.sleep(0.05)
                else:
                    raise RuntimeError("QML fixture did not become ready: " + log.read_text())
                time.sleep(1)
                if "ERROR" in log.read_text():
                    raise RuntimeError(log.read_text())
                indicators_before = counters(process.pid, env)
                before = host_context()
                values = []
                started = time.monotonic()
                while True:
                    value = snapshot(process.pid)
                    if value is None:
                        raise RuntimeError("Quickshell exited: " + log.read_text())
                    values.append(value)
                    elapsed = time.monotonic() - started
                    if elapsed >= seconds:
                        break
                    time.sleep(min(0.5, seconds - elapsed))
                indicators_after = counters(process.pid, env)
                pss = [value["pss_kib"] for value in values if value["pss_kib"] is not None]
                return {
                    "case": label, "panel_open": panel_open, "animations": True,
                    "playback_indicator_motion": animate, "window_visible": window_visible,
                    "seconds": elapsed,
                    "cpu_one_core_percent": (values[-1]["cpu_ticks"] - values[0]["cpu_ticks"]) / os.sysconf("SC_CLK_TCK") / elapsed * 100,
                    "pss_mib_median": statistics.median(pss) / 1024 if pss else None,
                    "rss_mib_median": statistics.median(value["rss_kib"] for value in values) / 1024,
                    "indicators_before": indicators_before, "indicators_after": indicators_after,
                    "samples": values, "host_before": before, "host_after": host_context(), "qml_log": log.read_text(),
                }
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=3)
        finally:
            bus.terminate()
            bus.wait(timeout=3)
            bus.stdout.close()
            bus.stderr.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=12)
    parser.add_argument("--output", type=Path, default=REPO / "perf-results/playback-motion.json")
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("At least one sampling second is required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="skylofi-motion-source-") as directory:
        frozen = Path(directory)
        for source in REPO.glob("*.qml"):
            shutil.copy2(source, frozen / source.name)
        shutil.copy2(REPO / "stations.json", frozen / "stations.json")
        report = {
            "method": "Same frozen actual QML UI; 480x620 offscreen software Qt window; real bar widget and one panel with layer-shell plumbing replaced by visible/open Item. General interface animations stay enabled in both cases; only equalizer_animation toggles the ongoing status motif. Bar transport replaced by fixture-only JSON process. Only Quickshell CPU/PSS sampled; child fixture, bus, Rust, mpv, GPU, FPS, audio and shared desktop-shell memory excluded. Two seconds settling. Active motif uses direct transforms at 8 Hz, not a frame-rate animation.",
            "source_sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(frozen.glob("*.qml"))},
            "cases": [],
        }
        for case in (("panel_static", True, False, True), ("panel_ongoing", True, True, True),
                     ("bar_static", False, False, True), ("bar_ongoing", False, True, True),
                     ("all_hidden", True, True, False)):
            print(case[0], flush=True)
            result = measure(frozen, *case, args.seconds)
            report["cases"].append(result)
            args.output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({key: value for key, value in result.items() if key not in ("samples", "qml_log", "host_before", "host_after")}), flush=True)


if __name__ == "__main__":
    main()
