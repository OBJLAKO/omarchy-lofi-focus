#!/usr/bin/env python3
"""Bounded, physically silent 3.5 mixer measurements in private player fixtures.

Uses real CPAL/ALSA for Rust, mpv --ao=null for the legacy comparison. Master
volume is zero before playback starts. No installed plugin or live state changes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE / 'tests'))
from backend_fixture import SOURCE as FIXTURE_SOURCE
from player_test import PlayerTest
from perf_baseline import host_context
from perf_live import snapshot


def details(pid):
    value = snapshot(pid)
    if value is None:
        return None
    proc = Path('/proc') / str(pid)
    value['fds'] = len(list((proc / 'fd').iterdir()))
    names = []
    for path in (proc / 'task').glob('*/comm'):
        try:
            names.append(path.read_text().strip())
        except FileNotFoundError:
            # Teardown can finish between enumerating and reading a task.
            pass
    value['thread_names'] = sorted(names)
    value['threads'] = len(value['thread_names'])
    value['decoder_threads'] = value['thread_names'].count('skylofi-decode')
    value['output_threads'] = value['thread_names'].count('cpal_alsa_out')
    return value


def processes(fixture):
    result = {}
    for path in (fixture.base / 'runtime/sky.lofi').glob('*.pid'):
        try:
            pid = int(path.read_text())
            if snapshot(pid):
                result[path.stem] = pid
        except (OSError, ValueError):
            pass
    return result


def controller(fixture):
    return int((fixture.base / 'runtime/sky.lofi/controller.pid').read_text())


def sample(fixture, seconds):
    targets = processes(fixture)
    rows = {name: [] for name in targets}
    started = time.monotonic()
    while True:
        for name, pid in targets.items():
            row = details(pid)
            if row is None:
                raise RuntimeError('Sampled process disappeared: ' + name)
            rows[name].append(row)
        if time.monotonic() - started >= seconds:
            break
        time.sleep(min(0.5, max(0, seconds - (time.monotonic() - started))))
    elapsed = time.monotonic() - started
    result = []
    for name, values in rows.items():
        if values[0]['start'] != values[-1]['start']:
            raise RuntimeError('Sampled process changed identity: ' + name)
        pss = [row['pss_kib'] for row in values if row['pss_kib'] is not None]
        result.append({
            'role': name,
            'cpu_one_core_percent': (values[-1]['cpu_ticks'] - values[0]['cpu_ticks']) / os.sysconf('SC_CLK_TCK') / elapsed * 100,
            'pss_mib_median': statistics.median(pss) / 1024 if pss else None,
            'rss_mib_median': statistics.median(row['rss_kib'] for row in values) / 1024,
            'fds_median': statistics.median(row['fds'] for row in values),
            'threads_median': statistics.median(row['threads'] for row in values),
            'decoder_threads_median': statistics.median(row['decoder_threads'] for row in values),
            'samples': values,
        })
    return {
        'seconds': elapsed,
        'processes': result,
        'total_cpu_one_core_percent': sum(row['cpu_one_core_percent'] for row in result),
        'total_pss_mib_median_sum': sum(row['pss_mib_median'] for row in result if row['pss_mib_median'] is not None),
        'nature_mpv_processes': len([name for name in targets if name.startswith('nature-')]),
    }


def make_fixture(binary, engine):
    os.environ['LOFI_TEST_BACKEND'] = 'rust'
    os.environ['SKYLOFI_NATIVE'] = str(binary)
    fixture = PlayerTest(methodName='test_lifecycle_and_settings')
    fixture.setUp()
    fixture.env['SKYLOFI_NATURE_ENGINE'] = engine
    fixture.env.pop('SKYLOFI_AUDIO_OUTPUT', None)
    # State/sockets stay private; only the explicitly silent output connects to
    # the existing host audio service through its original runtime directory.
    real_runtime = os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')
    fixture.env['PIPEWIRE_RUNTIME_DIR'] = os.environ.get('PIPEWIRE_RUNTIME_DIR', real_runtime)
    fixture.env['PULSE_RUNTIME_PATH'] = os.environ.get('PULSE_RUNTIME_PATH', str(Path(real_runtime) / 'pulse'))
    fixture.bus = subprocess.Popen(
        ['dbus-daemon', '--nofork', '--print-address=1', '--config-file=' + str(SOURCE / 'tests/dbus-no-activation.conf')],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    fixture.env['DBUS_SESSION_BUS_ADDRESS'] = fixture.bus.stdout.readline().strip()
    if not fixture.env['DBUS_SESSION_BUS_ADDRESS']:
        raise RuntimeError('Private D-Bus did not start')
    # PlayerTest preserves the legacy nine-layer catalog. Restore every bundled
    # ambience while retaining its private silence URLs for all network sources.
    catalog = json.loads((fixture.plugin / 'stations.json').read_text())
    original = json.loads((FIXTURE_SOURCE / 'stations.json').read_text())
    ambience = next(category for category in original['categories'] if category['id'] == 'ambience')
    next(category for category in catalog['categories'] if category['id'] == 'ambience')['stations'] = ambience['stations']
    (fixture.plugin / 'stations.json').write_text(json.dumps(catalog))
    fixture.nature_ids = [station['id'] for station in ambience['stations']]
    fixture.action('status')
    fixture.action('vol', 'master', '0')
    fixture.action('ui', 'fade', 'off')
    fixture.action('bg', 'off')
    fixture.action('wander', 'off')
    return fixture


def close(fixture):
    try:
        fixture.tearDown()
    finally:
        fixture.bus.terminate()
        fixture.bus.wait(timeout=3)
        fixture.bus.stdout.close()
        fixture.bus.stderr.close()


def stopped(fixture, wait_output=True):
    started = time.monotonic()
    fixture.action('stop')
    fixture.wait_for(lambda: not any(row['running'] for row in fixture.status()['nature_layers']))
    fixture.wait_for(lambda: details(controller(fixture))['decoder_threads'] == 0)
    time.sleep(0.1)
    pending = details(controller(fixture))
    if wait_output:
        fixture.wait_for(lambda: details(controller(fixture))['output_threads'] == 0, timeout=3)
    row = details(controller(fixture))
    row['after_100ms'] = pending
    row['observed_stop_seconds'] = time.monotonic() - started
    return row


def configure(fixture, count, effects):
    fixture.action('stop')
    for index, identity in enumerate(fixture.nature_ids):
        fixture.action('nature', identity, 'on' if index < count else 'off')
        if index < count:
            for key, value in [('distance', 35 if effects else 0), ('reflections', 70 if effects else 0),
                               ('echo', 20 if effects else 0), ('softness', 25 if effects else 0),
                               ('pan', (-40 if index % 2 else 40) if effects else 0), ('width', 80 if effects else 100)]:
                fixture.action('layer', identity, key, str(value))
    fixture.action('room', 'reflections', '65' if effects else '0')
    fixture.action('play')
    fixture.wait_for(lambda: sum(row['running'] for row in fixture.status()['nature_layers']) == count)
    state = fixture.status()
    if state['master_volume'] != 0 or state['nature_engine'] != fixture.env['SKYLOFI_NATURE_ENGINE']:
        raise RuntimeError('Incorrect silent output or mixer selection')
    time.sleep(0.6)


def cycles(fixture, count):
    stopped(fixture)
    for identity in fixture.nature_ids:
        fixture.action('nature', identity, 'off')
    baseline = details(controller(fixture))
    rows = []
    identity = fixture.nature_ids[0]
    for index in range(count):
        fixture.action('nature', identity, 'on')
        fixture.action('play')
        fixture.wait_for(lambda: fixture.status()['noise_running'])
        fixture.action('pause')
        fixture.action('nature', identity, 'off')
        fixture.wait_for(lambda: details(controller(fixture))['decoder_threads'] == 0)
        fixture.action('nature', identity, 'on')
        fixture.action('resume')
        fixture.wait_for(lambda: fixture.status()['noise_running'])
        row = stopped(fixture, wait_output=False)
        row['cycle'] = index + 1
        rows.append(row)
        print(f'cycle {index + 1}/{count}: {row["threads"]} threads, {row["fds"]} FDs, {row["pss_kib"]} KiB PSS', flush=True)
    started = time.monotonic()
    fixture.wait_for(lambda: details(controller(fixture))['output_threads'] == 0, timeout=3)
    settled = details(controller(fixture))
    if settled['decoder_threads'] or settled['fds'] != baseline['fds'] or settled['threads'] != baseline['threads']:
        raise RuntimeError('Stopped fixture resources did not return to the baseline')
    return {
        'baseline': baseline, 'stopped_samples': rows, 'settled': settled,
        'settle_seconds_after_last_snapshot': time.monotonic() - started,
        'note': 'Each cycle starts, pauses, removes the last source, re-adds while paused, resumes and stops. 100 ms snapshots intentionally capture rapid reuse; final snapshot waits for the output to close and asserts baseline FDs/threads.',
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--native-binary', type=Path, required=True)
    parser.add_argument('--seconds', type=float, default=10)
    parser.add_argument('--cycles', type=int, default=20)
    parser.add_argument('--lifecycle-only', action='store_true', help='Final 9-layer steady smoke plus rapid cycles after an output-lifecycle change')
    parser.add_argument('--output', type=Path, default=SOURCE / 'docs/perf/space-3.5.json')
    args = parser.parse_args()
    binary = args.native_binary.resolve()
    report = {
        'host': host_context(),
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'git_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SOURCE, text=True).strip(),
        'git_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=SOURCE, text=True).strip()),
        'native_source_sha256': {str(path.relative_to(SOURCE)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((SOURCE / 'native/src').glob('*.rs'))},
        'method': 'Private XDG state/runtime/catalog; private D-Bus without activation; real CPAL/ALSA default device for Rust local sources; physically silent master=0 before playback; one main mpv --ao=null local-silence source; Voice off; fades/wander off; 0.5s /proc samples. Effect settings are recorded below. PSS totals include all fixture-owned controller and mpv processes, excluding the private D-Bus and measurement process.',
        'effect_settings': {'dry': {'distance': 0, 'reflections': 0, 'echo': 0, 'softness': 0, 'pan': 0, 'width': 100, 'room_reflections': 0},
                            'wet': {'distance': 35, 'reflections': 70, 'echo': 20, 'softness': 25, 'pan': [-40, 40], 'width': 80, 'room_reflections': 65}},
        'cases': [],
    }
    fixture = make_fixture(binary, 'rust')
    try:
        report['initial_stopped'] = details(controller(fixture))
        groups = [(True, (9,))] if args.lifecycle_only else [(False, (0, 1, 9, 16)), (True, (0, 1, 9, 16))]
        for effects, counts in groups:
            for count in counts:
                configure(fixture, count, effects)
                result = sample(fixture, args.seconds)
                if result['nature_mpv_processes']:
                    raise RuntimeError('The Rust mixer unexpectedly launched nature mpv processes')
                result.update({'engine': 'rust', 'layers': count, 'effects': effects, 'phase': 'playing'})
                if args.lifecycle_only:
                    fixture.action('pause')
                    fixture.wait_for(lambda: fixture.status()['paused'])
                    paused = sample(fixture, args.seconds)
                    paused.update({'engine': 'rust', 'layers': count, 'effects': effects, 'phase': 'paused'})
                    report['cases'].append(paused)
                result['stopped'] = stopped(fixture)
                report['cases'].append(result)
                print(f'rust {count} layers effects={effects}: {result["total_cpu_one_core_percent"]:.2f}% core, {result["total_pss_mib_median_sum"]:.2f} MiB PSS', flush=True)
        report['cycles'] = cycles(fixture, args.cycles)
    finally:
        close(fixture)
    if args.lifecycle_only:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(str(args.output), flush=True)
        return
    fixture = make_fixture(binary, 'mpv')
    try:
        configure(fixture, 9, False)
        result = sample(fixture, args.seconds)
        result.update({'engine': 'mpv', 'layers': 9, 'effects': False})
        result['stopped'] = stopped(fixture)
        report['cases'].append(result)
        print(f'mpv 9 layers: {result["total_cpu_one_core_percent"]:.2f}% core, {result["total_pss_mib_median_sum"]:.2f} MiB PSS', flush=True)
    finally:
        close(fixture)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(str(args.output), flush=True)


if __name__ == '__main__':
    main()
