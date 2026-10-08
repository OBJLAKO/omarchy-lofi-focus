#!/usr/bin/env python3
"""Silent real-output coverage smoke and lifecycle check; no live-state writes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from perf_space import SOURCE, close, configure, cycles, make_fixture, sample, stopped


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--native-binary', type=Path, required=True)
    parser.add_argument('--seconds', type=float, default=8)
    parser.add_argument('--cycles', type=int, default=20)
    parser.add_argument('--baseline-only', action='store_true', help='Compare the previous 3.5 field without sending coverage commands or running cycles.')
    parser.add_argument('--output', type=Path, default=SOURCE / 'docs/perf/coverage-3.5.json')
    args = parser.parse_args()
    binary = args.native_binary.resolve()
    report = {
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'git_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SOURCE, text=True).strip(),
        'native_source_sha256': {} if args.baseline_only else {str(p.relative_to(SOURCE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((SOURCE / 'native/src').glob('*.rs'))},
        'baseline_only': args.baseline_only,
        'method': f'Private XDG/catalog/D-Bus; real CPAL output with master0 before play, local main mpv --ao=null. One logical core=100%. {args.seconds:g}-second samples; same16 wet layers. ' + ('Previous field with width100, no coverage commands; source identity belongs to the recorded old binary, not current source hashes. ' if args.baseline_only else 'Coverage0/50/100. ') + 'No live plugin/settings changes. Short smoke, not an audible-quality or long-soak guarantee.',
        'effect_settings': {'layers': 16, 'distance': 35, 'reflections': 70, 'echo': 20, 'softness': 25, 'pan': [-40, 40], 'width': 100, 'room_reflections': 65},
        'cases': [],
    }
    fixture = make_fixture(binary, 'rust')
    try:
        for coverage in ((None,) if args.baseline_only else (0, 50, 100)):
            configure(fixture, 16, True)
            for identity in fixture.nature_ids[:16]:
                fixture.action('layer', identity, 'width', '100')
                if coverage is not None:
                    fixture.action('layer', identity, 'coverage', str(coverage))
            result = sample(fixture, args.seconds)
            result.update({'layers': 16, 'coverage': coverage, 'phase': 'playing'})
            report['cases'].append(result)
            print(f'coverage{coverage}: {result["total_cpu_one_core_percent"]:.2f}% core / {result["total_pss_mib_median_sum"]:.2f} MiB PSS', flush=True)
        fixture.action('pause')
        result = sample(fixture, args.seconds)
        result.update({'layers': 16, 'coverage': None if args.baseline_only else 100, 'phase': 'paused'})
        report['cases'].append(result)
        report['stopped'] = stopped(fixture)
        if not args.baseline_only:
            report['cycles'] = cycles(fixture, args.cycles)
    finally:
        close(fixture)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(args.output)


if __name__ == '__main__':
    main()
