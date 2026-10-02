#!/usr/bin/env python3
"""Read-only sample of live Skylofi processes; never saves media URLs or args."""
import argparse
import json
import os
from pathlib import Path
import statistics
import time


def snapshot(pid):
    base = Path('/proc') / str(pid)
    try:
        fields = (base / 'stat').read_text().rsplit(')', 1)[1].split()
        status = dict(line.split(':', 1) for line in (base / 'status').read_text().splitlines() if ':' in line)
        pss = None
        try:
            rollup = dict(line.split(':', 1) for line in (base / 'smaps_rollup').read_text().splitlines() if ':' in line)
            pss = int(rollup['Pss'].split()[0])
        except (OSError, KeyError):
            pass
        return {'start': int(fields[19]), 'cpu_ticks': int(fields[11]) + int(fields[12]),
                'rss_kib': int(status.get('VmRSS', '0').split()[0]), 'pss_kib': pss,
                'voluntary': int(status.get('voluntary_ctxt_switches', '0')),
                'involuntary': int(status.get('nonvoluntary_ctxt_switches', '0'))}
    except (OSError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=float, default=20)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    targets = {}
    for directory in Path('/proc').iterdir():
        if not directory.name.isdecimal():
            continue
        try:
            argv = (directory / 'cmdline').read_bytes().split(b'\0')
        except OSError:
            continue
        if any(b'/sky.lofi/' in arg for arg in argv):
            role = 'mpv' if argv[0].endswith(b'mpv') else ('mpris' if any(arg.endswith(b'lofi-mpris') for arg in argv) else 'controller')
            targets[int(directory.name)] = role
        elif argv and argv[0].endswith(b'quickshell') and any(b'/omarchy/shell' in arg for arg in argv):
            targets[int(directory.name)] = 'whole_quickshell_host'
    start = time.monotonic()
    samples = {pid: [] for pid in targets}
    while True:
        for pid in targets:
            value = snapshot(pid)
            if value:
                samples[pid].append(value)
        elapsed = time.monotonic() - start
        if elapsed >= args.seconds:
            break
        time.sleep(min(1, args.seconds - elapsed))
    results = []
    for pid, values in samples.items():
        if len(values) < 2 or values[0]['start'] != values[-1]['start']:
            continue
        first, last = values[0], values[-1]
        results.append({'pid': pid, 'role': targets[pid],
                        'cpu_one_core_percent': (last['cpu_ticks'] - first['cpu_ticks']) / os.sysconf('SC_CLK_TCK') / elapsed * 100,
                        'rss_mib_median': statistics.median(v['rss_kib'] for v in values) / 1024,
                        'pss_mib_median': statistics.median(v['pss_kib'] for v in values if v['pss_kib'] is not None) / 1024 if first['pss_kib'] is not None else None,
                        'voluntary_context_switches_per_second': (last['voluntary'] - first['voluntary']) / elapsed})
    report = {'seconds': elapsed, 'clock_tick_seconds': 1 / os.sysconf('SC_CLK_TCK'),
              'processes': results, 'note': 'Existing processes only; Quickshell is shared by all plugins. No UI or playback changes.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
