#!/usr/bin/env python3
"""Measure actual old/new QML animation CPU in a disposable offscreen host.

This isolates the visual layer: fixture status, no BarWidget/backend/audio,
fixed viewport, installed Omarchy UI types, private no-activation D-Bus.
It is not an on-screen GPU/FPS benchmark or the shared desktop shell's RSS.
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

from perf_baseline import SOURCE, host_context
from perf_live import snapshot


def measure(source, phase, seconds):
    with tempfile.TemporaryDirectory(prefix='skylofi-qml-perf-') as directory:
        stage = Path(directory)
        for name in ('Commons', 'Ui'):
            (stage/name).symlink_to(Path('/usr/share/omarchy/shell')/name)
        plugin = stage/'Plugin'
        plugin.mkdir()
        for path in source.glob('*.qml'):
            shutil.copyfile(path, plugin/path.name)
        shutil.copyfile(source/'stations.json', plugin/'stations.json')
        panel = plugin/'Panel.qml'
        panel.write_text(panel.read_text().replace('KeyboardPanel {', 'PreviewSurface {'))
        (plugin/'PreviewSurface.qml').write_text('''import QtQuick
Item {
 property var anchorItem
 property var owner
 property var bar
 property bool open
 property bool centerOnBar
 property var focusTarget
 property real contentWidth
 property real contentHeight
 width: parent.width
 height: parent.height
 visible: open
 function fittedContentWidth(value) { return value }
 function fittedContentHeight(value) { return value }
}
''')
        transition = 'close()' if phase == 'closed' else ('settingsOpen=true; open()' if phase == 'settings' else 'open()')
        (stage/'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "Plugin" as Lofi
Window {
 width: 478; height: 696; visible: true; color: Color.background
 Lofi.Panel {
  x: 14; y: 16; width: 430; height: 644
  Component.onCompleted: {
   applyStatus(JSON.stringify({running:true,paused:false,main_running:true,main_state:"playing",station:"lofi-lilo",name:"Lilo-Fi Radio",category:"lofi",category_name:"Lo-fi radio",main_volume:65,master_volume:80,mix:true,bg_station:"talk-bbc-world",bg_name:"BBC World Service",bg_volume:20,nature_layers:[{id:"noise-rain",name:"Rain",enabled:true,running:true,volume:25}],animations:true,reveal_animations:false,fade_enabled:true,fade_seconds:3,ducking:true,duck_level:35}))
   ''' + transition + '''
  }
 }
 Timer { interval: 1000; running: true; onTriggered: console.log("QML_PERF_READY") }
}
''')
        runtime = stage/'runtime'
        runtime.mkdir(mode=0o700)
        env = os.environ | {'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': '', 'QT_STYLE_OVERRIDE': 'Basic', 'XDG_RUNTIME_DIR': str(runtime)}
        env.pop('WAYLAND_DISPLAY', None)
        bus = subprocess.Popen(['dbus-daemon', '--config-file=' + str(SOURCE/'tests/dbus-no-activation.conf'), '--nofork', '--print-address=1'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        env['DBUS_SESSION_BUS_ADDRESS'] = bus.stdout.readline().strip()
        log = stage/'quickshell.log'
        try:
            with log.open('w') as output:
                process = subprocess.Popen(['quickshell', '-p', str(stage), '--no-color'], env=env, stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    if 'QML_PERF_READY' in log.read_text() and process.poll() is None:
                        break
                    if process.poll() is not None:
                        raise RuntimeError(log.read_text())
                    time.sleep(.05)
                else:
                    raise RuntimeError('QML fixture timed out: ' + log.read_text())
                time.sleep(1)
                before = host_context()
                values = []
                started = time.monotonic()
                while True:
                    value = snapshot(process.pid)
                    if value is None:
                        raise RuntimeError('QML process exited: ' + log.read_text())
                    values.append(value)
                    elapsed = time.monotonic() - started
                    if elapsed >= seconds:
                        break
                    time.sleep(min(.5, seconds - elapsed))
                pss = [sample['pss_kib'] for sample in values if sample['pss_kib'] is not None]
                return {'phase': phase, 'seconds': elapsed, 'cpu_one_core_percent': (values[-1]['cpu_ticks'] - values[0]['cpu_ticks']) / os.sysconf('SC_CLK_TCK') / elapsed * 100,
                        'rss_mib_median': statistics.median(sample['rss_kib'] for sample in values) / 1024,
                        'pss_mib_median': statistics.median(pss) / 1024 if pss else None,
                        'voluntary_context_switches_per_second': (values[-1]['voluntary'] - values[0]['voluntary']) / elapsed,
                        'samples': values, 'host_before': before, 'host_after': host_context(), 'qml_log': log.read_text()}
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
    parser.add_argument('--python-source', type=Path, required=True)
    parser.add_argument('--seconds', type=float, default=15)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error('At least one sampling second required')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = {'method': 'Actual QML; fixture playing state and animations on; offscreen Qt renderer, 478x696 viewport; disposable Quickshell process per scenario; installed Omarchy UI types and user theme; layer-shell plumbing replaced by visible/open Item; no backend, audio or BarWidget; private no-activation bus; two seconds settling. This measures process CPU and memory, not GPU, FPS or shared desktop shell memory.',
              'qml_source_sha256': {label: {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(source.glob('*.qml'))}
                                    for label, source in (('python_original_qml', args.python_source), ('rust_redesign_qml', SOURCE))},
              'cases': []}
    for phase in ('closed', 'listening', 'settings'):
        for label, source in (('python_original_qml', args.python_source), ('rust_redesign_qml', SOURCE)):
            print(label + ': ' + phase, flush=True)
            result = measure(source, phase, args.seconds)
            result['source'] = label
            report['cases'].append(result)
            args.output.write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps({key: value for key, value in result.items() if key not in ('samples', 'qml_log', 'host_before', 'host_after')}), flush=True)


if __name__ == '__main__':
    main()
