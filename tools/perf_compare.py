#!/usr/bin/env python3
"""Interleave pinned Python and explicit release Rust commands on one host.

The separate full runs measure CPU/PSS without doubling the audio workload.
This additional test randomizes language/transport order to reduce time-varying
CPU governor and host-load bias in command latency. Each has a private D-Bus.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import random
import select
import subprocess
import time

from perf_baseline import Fixture, SOURCE, host_context, summary


class Bus:
    def __init__(self):
        self.process = subprocess.Popen(['dbus-daemon', '--nofork', '--print-address=1', '--config-file=' + str(SOURCE/'tests/dbus-no-activation.conf')], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if not select.select([self.process.stdout], [], [], 5)[0]:
            raise RuntimeError('Private benchmark bus timed out')
        self.address = self.process.stdout.readline().strip()
        if not self.address:
            raise RuntimeError('Private benchmark bus failed: ' + self.process.stderr.read())
    def close(self):
        self.process.terminate()
        self.process.wait(timeout=3)
        self.process.stdout.close()
        self.process.stderr.close()


def fixture_on_bus(source, backend, binary, bus):
    prior = os.environ.get('DBUS_SESSION_BUS_ADDRESS')
    os.environ['DBUS_SESSION_BUS_ADDRESS'] = bus.address
    try:
        return Fixture(source, backend, binary)
    finally:
        if prior is None:
            os.environ.pop('DBUS_SESSION_BUS_ADDRESS', None)
        else:
            os.environ['DBUS_SESSION_BUS_ADDRESS'] = prior


def prepare(fixture, channels):
    fixture.call(['bg', 'off' if channels <= 1 else 'talk-bbc-world'])
    if channels:
        fixture.call(['play'])
    for identity in fixture.nature[:max(0, channels - 2)]:
        fixture.call(['nature', identity, 'on'])


def measure(args, channels):
    buses, fixtures = [], {}
    try:
        for backend in ('python', 'rust'):
            bus = Bus()
            buses.append(bus)
            fixture = fixture_on_bus(args.python_source if backend == 'python' else SOURCE, backend, args.native_binary if backend == 'rust' else None, bus)
            fixtures[backend] = fixture
            prepare(fixture, channels)
        time.sleep(1.2)
        result = {'channels_per_backend': channels, 'host_before': host_context(), 'commands': {}, 'cli_child_cpu_ms': {}}
        if args.paired_cpu_seconds:
            # No commands, profiles or benchmark adapters during this phase.
            # Both decoder workloads remain active on the same host window.
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = {backend: pool.submit(fixture.sample, args.paired_cpu_seconds) for backend, fixture in fixtures.items()}
                result['paired_steady_cpu'] = {backend: future.result() for backend, future in futures.items()}
        rng = random.Random(42)
        for resident in (False, True):
            if resident:
                for fixture in fixtures.values():
                    fixture.start_resident()
            cases = [(backend, operation) for backend in fixtures for operation in ('status', 'volume', 'pause_resume_pair') if channels or operation != 'pause_resume_pair']
            elapsed, cpu = {case: [] for case in cases}, {case: [] for case in cases}
            for backend, operation in cases:
                for _ in range(5):
                    fixtures[backend].call(['status'], resident=resident)
            for index in range(args.samples):
                rng.shuffle(cases)
                for case in cases:
                    backend, operation = case
                    fixture = fixtures[backend]
                    if operation == 'status':
                        wall = fixture.call(['status'], resident=resident)
                    elif operation == 'volume':
                        wall = fixture.call(['vol', 'master', str(40 + index % 40)], resident=resident)
                    else:
                        wall = fixture.call(['pause'], resident=resident)
                        first_cpu = fixture.last_child_cpu_ms
                        wall += fixture.call(['resume'], resident=resident)
                        fixture.last_child_cpu_ms += first_cpu
                    # The original Python CLI deliberately emits no stdout for
                    # volume/transport actions; status and adapters emit JSON.
                    if operation == 'status' or resident or backend == 'rust':
                        json.loads(fixture.last_stdout)
                    elapsed[case].append(wall)
                    cpu[case].append(fixture.last_child_cpu_ms)
            for case, values in elapsed.items():
                name = '_'.join((case[0], 'resident' if resident else 'cli', case[1]))
                result['commands'][name] = summary(values)
                if not resident:
                    result['cli_child_cpu_ms'][name] = summary(cpu[case])
        result['host_after'] = host_context()
        return result
    finally:
        for fixture in fixtures.values():
            fixture.close()
        for bus in buses:
            bus.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--python-source', type=Path, required=True)
    parser.add_argument('--native-binary', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=50)
    parser.add_argument('--paired-cpu-seconds', type=float, default=0, help='Optional simultaneous steady CPU/PSS phase, no command traffic')
    parser.add_argument('--channels', type=int, nargs='+', default=[0, 1, 3, 11])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error('At least one sample is required')
    if args.paired_cpu_seconds < 0:
        parser.error('Paired CPU interval must be nonnegative')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = {'host_before': host_context(), 'samples': args.samples, 'paired_cpu_seconds': args.paired_cpu_seconds,
              'python_backend_sha256': hashlib.sha256((args.python_source/'lofi_backend.py').read_bytes()).hexdigest(),
              'native_binary_sha256': hashlib.sha256(args.native_binary.read_bytes()).hexdigest(),
              'method': 'Separate private no-activation buses and XDG fixtures; real mpv ao=null; identical original catalog/local WAV; fades off; five warmups; seeded randomized backend and operation order; CLI then resident phases. Both audio fixtures remain active; use standalone full runs for memory/CPU totals. Resident Python is unchanged reference logic with stdin adapter, Rust uses production stdio.',
              'cases': []}
    for channels in args.channels:
        print('Interleaving channels=%d per backend' % channels, flush=True)
        report['cases'].append(measure(args, channels))
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({name: {k: v for k, v in values.items() if k != 'raw_ms'} for name, values in report['cases'][-1]['commands'].items()}), flush=True)


if __name__ == '__main__':
    main()
