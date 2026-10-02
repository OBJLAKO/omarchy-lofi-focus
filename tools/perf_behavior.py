#!/usr/bin/env python3
"""Measure actual mpv duck/fade completion, separately from command replies."""
import argparse
import hashlib
import json
from pathlib import Path
import time

from perf_baseline import Fixture, SOURCE, host_context, mpv_property, summary


def await_values(fixture, property_name, expected, timeout=5):
    deadline = time.monotonic() + timeout
    values = {}
    while time.monotonic() < deadline:
        try:
            values = {channel: mpv_property(fixture.runtime/('sky.lofi/sockets/' + channel + '.sock'), property_name) for channel in expected}
        except OSError:
            time.sleep(.01)
            continue
        if all((values[channel] == target if isinstance(target, bool) else values[channel] is not None and abs(values[channel] - target) < .1) for channel, target in expected.items()):
            return values
        time.sleep(.01)
    raise RuntimeError('Actual mpv properties did not reach %s: %s' % (expected, values))


def measure(args, backend):
    fixture = Fixture(args.python_source if backend == 'python' else SOURCE, backend, args.native_binary if backend == 'rust' else None)
    try:
        fixture.call(['play'])
        fixture.call(['nature', 'noise-rain', 'on'])
        fixture.call(['ui', 'duckLevel', '20'])
        fixture.call(['vol', 'main', '65'])
        fixture.call(['vol', 'bg', '20'])
        fixture.call(['vol', 'noise-rain', '25'])
        fixture.call(['vol', 'master', '100'])
        channels = {'main':65, 'bg':20, 'nature-noise-rain':25}
        await_values(fixture, 'volume', channels)
        result = {'backend': backend, 'host_before': host_context(), 'duck_down_applied': [], 'duck_up_applied': [], 'fade_pause_acknowledged': [], 'fade_pause_applied': [], 'fade_resume_applied': [], 'volume_at_committed_pause': []}
        state = fixture.runtime/'voxtype/state'
        for _ in range(args.samples):
            for recording, key, gain in ((True, 'duck_down_applied', .2), (False, 'duck_up_applied', 1)):
                started = time.perf_counter_ns()
                state.write_text('recording' if recording else 'idle')
                await_values(fixture, 'volume', {channel:value*gain for channel,value in channels.items()})
                result[key].append((time.perf_counter_ns() - started)/1e6)
        fixture.call(['ui', 'fadeSeconds', '1'])
        fixture.call(['ui', 'fade', 'on'])
        for _ in range(args.samples):
            started = time.perf_counter_ns()
            result['fade_pause_acknowledged'].append(fixture.call(['pause']))
            await_values(fixture, 'pause', {channel:True for channel in channels})
            result['fade_pause_applied'].append((time.perf_counter_ns() - started)/1e6)
            result['volume_at_committed_pause'].append(await_values(fixture, 'volume', {channel:0 for channel in channels}))
            started = time.perf_counter_ns()
            fixture.call(['resume'])
            await_values(fixture, 'pause', {channel:False for channel in channels})
            await_values(fixture, 'volume', channels)
            result['fade_resume_applied'].append((time.perf_counter_ns() - started)/1e6)
        for key in ('duck_down_applied', 'duck_up_applied', 'fade_pause_acknowledged', 'fade_pause_applied', 'fade_resume_applied'):
            result[key] = summary(result[key])
        result['host_after'] = host_context()
        return result
    finally:
        fixture.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--python-source', type=Path, required=True)
    parser.add_argument('--native-binary', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error('At least one sample required')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    report = {'native_binary_sha256': hashlib.sha256(args.native_binary.read_bytes()).hexdigest(),
              'method': 'Same isolated local audio fixtures as perf_baseline; 3 actual mpv channels; VoxType idle/recording via fixture state; configured20% duck, master100, music65/voice20/rain25; physical properties within0.1; no command in timed duck path; configuredfade1s in,0.6s out; pause acknowledgement separate from committed pause, silence required on all channels.', 'cases': []}
    for backend in ('python', 'rust'):
        print('Actual applied duck/fade: ' + backend, flush=True)
        report['cases'].append(measure(args, backend))
        args.output.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({key:value for key,value in report['cases'][-1].items() if key not in ('host_before', 'host_after')}), flush=True)


if __name__ == '__main__':
    main()
