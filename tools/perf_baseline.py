#!/usr/bin/env python3
"""Offline performance harness for pinned Python and explicit Rust builds.

Run on the private no-activation D-Bus from tests/dbus-no-activation.conf.
Every audio channel uses real mpv, its real bundled codec, and --ao=null.
Settings, VoxType config, sockets and catalog belong to a temporary fixture.
Raw wall times, child CPU and /proc samples are preserved in JSON.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import pstats
import queue
import random
import resource
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import time
import threading
import wave

sys.dont_write_bytecode = True
from perf_live import snapshot

SOURCE = Path(__file__).resolve().parents[1]


def summary(values):
    ordered = sorted(values)
    return {'n': len(values), 'median_ms': statistics.median(values),
            'p95_ms': ordered[max(0, int(len(values) * .95 + .999999) - 1)],
            'min_ms': min(values), 'max_ms': max(values), 'raw_ms': values}


def host_context():
    cpuinfo = Path('/proc/cpuinfo').read_text().splitlines()
    return {'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'loadavg': Path('/proc/loadavg').read_text().strip(),
            'cpu_model': next((line.split(':', 1)[1].strip() for line in cpuinfo if line.startswith('model name')), ''),
            'logical_cpus': os.cpu_count(),
            'cpu_frequency_mhz': [float(line.split(':', 1)[1]) for line in cpuinfo if line.startswith('cpu MHz')],
            'scaling_governor': {path.parent.parent.name: path.read_text().strip() for path in Path('/sys/devices/system/cpu').glob('cpu*/cpufreq/scaling_governor')}}


class Fixture:
    def __init__(self, source=SOURCE, backend='python', native_binary=None):
        self.backend = backend
        self.source = Path(source).resolve()
        self.temp = tempfile.TemporaryDirectory(prefix='lofi-perf-')
        self.base = Path(self.temp.name)
        self.plugin = self.base / 'plugin'
        shutil.copytree(self.source, self.plugin, ignore=shutil.ignore_patterns('.git', '__pycache__', 'perf-results', 'target'))
        # Pinning --source to an archived Git revision keeps the baseline
        # independent of concurrent implementation changes in the worktree.
        (self.plugin / 'tools').mkdir(exist_ok=True)
        shutil.copyfile(SOURCE / 'tools/perf_resident.py', self.plugin / 'tools/perf_resident.py')
        if backend == 'python':
            (self.plugin / 'lofi-player').write_text('#!/usr/bin/env python3\nimport sys\nsys.dont_write_bytecode = True\nfrom lofi_backend import main\nmain()\n')
            (self.plugin / 'lofi-player').chmod(0o755)
        elif native_binary:
            native = self.plugin / 'native/target/release/skylofi'
            native.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(native_binary, native)
            native.chmod(0o755)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        (self.bin / 'mpv').write_text('#!/bin/sh\nexec /usr/bin/mpv --ao=null --loop-file=inf "$@"\n')
        (self.bin / 'mpv').chmod(0o755)
        tone = self.base / 'silence.wav'
        with wave.open(str(tone), 'wb') as output:
            output.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
            output.writeframes(b'\0\0' * 48000 * 10)
        catalog = json.loads((self.plugin / 'stations.json').read_text())
        self.nature = []
        for category in catalog['categories']:
            for station in category['stations']:
                if category['id'] == 'ambience':
                    self.nature.append(station['id'])
                else:
                    station['url'] = str(tone)
                    station.pop('kind', None)
        (self.plugin / 'stations.json').write_text(json.dumps(catalog))
        self.runtime = self.base / 'runtime'
        self.runtime.mkdir(mode=0o700)
        config = self.base / 'config'
        (config / 'voxtype').mkdir(parents=True)
        (config / 'voxtype/config.toml').write_text('state_file = "auto"\n')
        (self.runtime / 'voxtype').mkdir()
        (self.runtime / 'voxtype/pid').write_text(str(os.getpid()))
        (self.runtime / 'voxtype/state').write_text('idle')
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.runtime), XDG_STATE_HOME=str(self.base / 'state'),
                        XDG_CONFIG_HOME=str(config), PATH=str(self.bin) + ':' + os.environ['PATH'], PYTHONDONTWRITEBYTECODE='1')
        if backend == 'rust' and native_binary:
            self.env['SKYLOFI_NATIVE'] = str(native)
        self.resident = None
        self.resident_queue = queue.Queue()
        self.request_id = 0
        self.last_stdout = ''
        self.startup_ms = self.call(['status'])
        self.call(['ui', 'fade', 'off'])

    def call(self, args, resident=False):
        started = time.perf_counter_ns()
        children_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        if resident:
            self.request_id += 1
            request = {'id': self.request_id, 'args': args} if self.backend == 'rust' else args
            self.resident.stdin.write(json.dumps(request) + '\n')
            self.resident.stdin.flush()
            deadline = time.monotonic() + 20
            while True:
                raw = self.resident_queue.get(timeout=max(.001, deadline - time.monotonic()))
                if not raw:
                    raise RuntimeError('Resident adapter exited')
                result = json.loads(raw)
                if self.backend == 'python' or result.get('id') == self.request_id:
                    break
            if not result['ok']:
                raise RuntimeError(result['error'])
            self.last_stdout = json.dumps(result['status' if self.backend == 'rust' else 'state'])
        else:
            result = subprocess.run([str(self.plugin / 'lofi-player'), *args], env=self.env, capture_output=True, text=True, timeout=20)
            if result.returncode:
                raise RuntimeError(result.stderr)
            self.last_stdout = result.stdout
        children_after = resource.getrusage(resource.RUSAGE_CHILDREN)
        self.last_child_cpu_ms = ((children_after.ru_utime + children_after.ru_stime) - (children_before.ru_utime + children_before.ru_stime)) * 1000
        return (time.perf_counter_ns() - started) / 1e6

    def start_resident(self):
        args = [str(self.plugin / 'lofi-player'), '--stdio'] if self.backend == 'rust' else [sys.executable, '-B', str(self.plugin / 'tools/perf_resident.py')]
        self.resident = subprocess.Popen(args, env=self.env,
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        def read_output():
            for line in self.resident.stdout:
                self.resident_queue.put(line)
            self.resident_queue.put('')
        self.resident_reader = threading.Thread(target=read_output, daemon=True)
        self.resident_reader.start()
        raw = self.resident_queue.get(timeout=10)
        if not raw or (self.backend == 'python' and raw.strip() != 'ready') or (self.backend == 'rust' and json.loads(raw).get('event') != 'status'):
            raise RuntimeError('Resident adapter failed to start')

    def stop_resident(self):
        if self.resident:
            self.resident.stdin.close()
            try:
                self.resident.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.resident.terminate()
                self.resident.wait(timeout=3)
            self.resident.stdout.close()
            self.resident.stderr.close()
            self.resident_reader.join(timeout=1)
            self.resident = None

    def processes(self):
        result = {}
        for path in (self.runtime / 'sky.lofi').glob('*.pid'):
            try:
                pid = int(path.read_text())
                if snapshot(pid):
                    result[path.stem] = pid
            except (OSError, ValueError):
                pass
        return result

    def sample(self, seconds, ui_poll=False, include_resident=False):
        targets = self.processes()
        if include_resident and self.resident:
            targets['stdio_client'] = self.resident.pid
        values = {role: [] for role in targets}
        children_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        start = time.monotonic()
        due = start + 2
        polls = 0
        while True:
            for role, pid in targets.items():
                value = snapshot(pid)
                if value:
                    values[role].append(value)
            now = time.monotonic()
            if now - start >= seconds:
                break
            if ui_poll and now >= due:
                self.call(['status'])
                polls += 1
                due += 2
            time.sleep(min(.5, max(0, seconds - (time.monotonic() - start))))
        elapsed = time.monotonic() - start
        children_after = resource.getrusage(resource.RUSAGE_CHILDREN)
        child_cpu = (children_after.ru_utime + children_after.ru_stime) - (children_before.ru_utime + children_before.ru_stime)
        rows = []
        for role, samples in values.items():
            if len(samples) < 2 or samples[0]['start'] != samples[-1]['start']:
                raise RuntimeError('A sampled process exited or changed identity: ' + role)
            first, last = samples[0], samples[-1]
            pss = [v['pss_kib'] for v in samples if v['pss_kib'] is not None]
            rows.append({'role': role, 'cpu_one_core_percent': (last['cpu_ticks'] - first['cpu_ticks']) / os.sysconf('SC_CLK_TCK') / elapsed * 100,
                         'rss_mib_median': statistics.median(v['rss_kib'] for v in samples) / 1024,
                         'pss_mib_median': statistics.median(pss) / 1024 if pss else None,
                         'voluntary_context_switches_per_second': (last['voluntary'] - first['voluntary']) / elapsed,
                         'samples': samples})
        return {'seconds': elapsed, 'status_processes': polls, 'status_process_cpu_percent': child_cpu / elapsed * 100, 'processes': rows}

    def close(self):
        self.stop_resident()
        try:
            self.call(['ui', 'fade', 'off'])
            self.call(['stop'])
            if self.backend == 'rust':
                self.call(['shutdown'])
        finally:
            self.temp.cleanup()


def mpv_property(path, property_name):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(1)
        client.connect(str(path))
        client.sendall((json.dumps({'command':['get_property', property_name], 'request_id':42}) + '\n').encode())
        with client.makefile() as stream:
            for _ in range(64):
                result = json.loads(stream.readline(65537))
                if result.get('request_id') == 42:
                    return result.get('data')
    raise RuntimeError('No matching mpv reply')


def mpv_volume(path):
    return mpv_property(path, 'volume')


def benchmark_case(channels, samples, seconds, output, source=SOURCE, backend='python', native_binary=None):
    fixture = Fixture(source, backend, native_binary)
    try:
        fixture.call(['bg', 'off' if channels <= 1 else 'talk-bbc-world'])
        if channels:
            fixture.call(['play'])
        for identity in fixture.nature[:max(0, channels - 2)]:
            fixture.call(['nature', identity, 'on'])
        time.sleep(1.2)
        if len([r for r in fixture.processes() if r == 'main' or r == 'bg' or r.startswith('nature-')]) != channels:
            raise RuntimeError('Unexpected channel count')
        measured = {'channels': channels, 'host_before': host_context(), 'cold_fixture_startup_ms': fixture.startup_ms,
                    'backend_only': fixture.sample(seconds),
                    'with_qml_status_poll_simulation': fixture.sample(seconds, ui_poll=True)}
        fixture.start_resident()
        if backend == 'rust':
            measured['with_production_stdio_subscription'] = fixture.sample(seconds, include_resident=True)
        resident_name = 'resident_' + backend
        times = {name: [] for name in ('cli_status', resident_name + '_status', 'cli_volume', resident_name + '_volume', 'cli_pause_resume_pair', resident_name + '_pause_resume_pair')}
        child_cpu = {name: [] for name in times if name.startswith('cli_')}
        operations = list(times)
        rng = random.Random(42)
        for warmup in range(5):
            fixture.call(['status'])
            fixture.call(['status'], resident=True)
        for index in range(samples):
            rng.shuffle(operations)
            for name in operations:
                resident = name.startswith('resident')
                if name.endswith('status'):
                    elapsed = fixture.call(['status'], resident=resident)
                    json.loads(fixture.last_stdout)
                elif name.endswith('volume'):
                    elapsed = fixture.call(['vol', 'master', str(40 + index % 40)], resident=resident)
                elif channels:
                    elapsed = fixture.call(['pause'], resident=resident)
                    first_cpu = fixture.last_child_cpu_ms
                    elapsed += fixture.call(['resume'], resident=resident)
                    fixture.last_child_cpu_ms += first_cpu
                else:
                    continue
                times[name].append(elapsed)
                if name in child_cpu:
                    child_cpu[name].append(fixture.last_child_cpu_ms)
        measured['commands'] = {name: summary(values) for name, values in times.items() if values}
        measured['cli_child_cpu_ms'] = {name: summary(values) for name, values in child_cpu.items() if values}
        measured[resident_name + '_memory'] = snapshot(fixture.resident.pid)
        if channels:
            fixture.call(['vol', 'master', '100'])
            applied = []
            for index in range(20):
                target = 30 + index % 2 * 40
                started = time.perf_counter_ns()
                fixture.call(['vol', 'main', str(target)], resident=True)
                deadline = time.monotonic() + 3
                while abs(mpv_volume(fixture.runtime / 'sky.lofi/sockets/main.sock') - target) > .1:
                    if time.monotonic() > deadline:
                        raise RuntimeError('Resident volume did not reach its target')
                    time.sleep(.002)
                applied.append((time.perf_counter_ns() - started) / 1e6)
            measured['single_resident_volume_call_to_mpv_applied'] = summary(applied)
        fixture.stop_resident()
        if channels:
            applied = []
            for index in range(20):
                target = 30 + index % 2 * 40
                started = time.perf_counter_ns()
                fixture.call(['vol', 'main', str(target)])
                fixture.call(['vol', 'master', '100'])
                # This metric includes two real CLI calls; report it explicitly.
                deadline = time.monotonic() + 3
                while abs(mpv_volume(fixture.runtime / 'sky.lofi/sockets/main.sock') - target) > .1:
                    if time.monotonic() > deadline:
                        raise RuntimeError('Volume did not reach its target')
                    time.sleep(.002)
                applied.append((time.perf_counter_ns() - started) / 1e6)
            measured['two_cli_volume_calls_to_mpv_applied'] = summary(applied)
            applied = []
            fixture.call(['vol', 'master', '100'])
            for index in range(20):
                target = 30 + index % 2 * 40
                started = time.perf_counter_ns()
                fixture.call(['vol', 'main', str(target)])
                deadline = time.monotonic() + 3
                while abs(mpv_volume(fixture.runtime / 'sky.lofi/sockets/main.sock') - target) > .1:
                    if time.monotonic() > deadline:
                        raise RuntimeError('Volume did not reach its target')
                    time.sleep(.002)
                applied.append((time.perf_counter_ns() - started) / 1e6)
            measured['single_cli_volume_call_to_mpv_applied'] = summary(applied)
        if backend == 'python':
            profile_path = output.parent / ('profile-%d.txt' % channels)
            program = fixture.plugin / 'lofi-player'
            prof = output.parent / ('profile-%d.pstats' % channels)
            result = subprocess.run([sys.executable, '-B', '-m', 'cProfile', '-o', str(prof), str(program), 'status'], env=fixture.env, capture_output=True, text=True, timeout=20)
            if result.returncode:
                raise RuntimeError(result.stderr)
            profile_text = io.StringIO()
            pstats.Stats(str(prof), stream=profile_text).strip_dirs().sort_stats('cumulative').print_stats(35)
            profile_path.write_text(profile_text.getvalue())
            measured['profile_summary'] = profile_path.name
        measured['host_after'] = host_context()
        return measured
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--samples', type=int, default=50)
    parser.add_argument('--seconds', type=float, default=15)
    parser.add_argument('--channels', type=int, nargs='+', default=[0, 1, 3, 11])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=SOURCE, help='Pinned source snapshot or worktree')
    parser.add_argument('--backend', choices=('python', 'rust'), default='python')
    parser.add_argument('--native-binary', type=Path, help='Explicit already-built Rust executable')
    args = parser.parse_args()
    if not os.environ.get('DBUS_SESSION_BUS_ADDRESS'):
        parser.error('Run through the private test dbus-run-session first')
    if args.samples < 1 or args.seconds < 1:
        parser.error('At least one sample and one sampling second are required')
    if args.backend == 'rust' and not args.native_binary:
        parser.error('Rust measurement requires --native-binary; implicit builds are prohibited')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result = {'git_base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SOURCE, text=True).strip(),
              'provenance_note': 'Git HEAD identifies the base revision, not uncommitted Rust source. Python reference comes from the explicit source snapshot; Rust identity is native_binary_sha256 and perf-results/native-build.json source hashes.',
              'source_path': str(args.source.resolve()), 'backend': args.backend,
              'source_hashes': {name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in ('lofi_backend.py', 'lofi_duck.py', 'stations.json')},
              'native_binary_sha256': hashlib.sha256(args.native_binary.read_bytes()).hexdigest() if args.native_binary else None,
              'host_before': host_context(),
              'python': sys.version, 'platform': platform.platform(),
              'mpv': subprocess.check_output(['/usr/bin/mpv', '--version'], text=True).splitlines()[0],
              'clock_tick_seconds': 1 / os.sysconf('SC_CLK_TCK'),
              'method': 'Warm filesystem cache; seeded randomized CLI/resident order; fades off; real mpv --ao=null; local WAV music/voice and original bundled nature loops; fixture VoxType idle; private D-Bus; 5 warmups. No Quickshell renderer or network startup.',
              'cases': []}
    for channels in args.channels:
        print('Measuring channels=%d' % channels, flush=True)
        result['cases'].append(benchmark_case(channels, args.samples, args.seconds, args.output, args.source, args.backend, args.native_binary))
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'channels': channels, 'commands': {name: {k: v for k, v in value.items() if k != 'raw_ms'} for name, value in result['cases'][-1]['commands'].items()}}), flush=True)
    print('Saved ' + str(args.output), flush=True)


if __name__ == '__main__':
    main()
