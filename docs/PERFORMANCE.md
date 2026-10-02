# Skylofi Rust experiment: measured performance

The experiment supports the persistent native controller and pushed QML
transport: at three channels, interleaved CLI status falls from 165 to 15 ms,
production volume reaches mpv in about 0.8 ms, and persistent control memory
falls from about 29 to 5 MiB PSS. The QML redesign separately lowers measured
offscreen listening CPU by about 78%. Rust is useful here as part of a new
control architecture; the experiment does not prove that language choice
alone causes those gains. Decoders still dominate the eleven-layer workload.

Measurements were made on 2026-10-02 against the original Python plugin at
`a3b79ad0be4879b34b4e940d1a46ec65865d6144` and the uncommitted Rust rework.
The measured release executable has SHA256
`c4faaebe80313affb9a6fac33cf99a9daab07d282870b264e450266b52a5bba2`.
[Build identity and native source hashes](../perf-results/native-build.json)
identify the experimental code; the Git base revision alone does not.

## What the experiment can establish

The implementation combines Rust with a persistent controller, cached mpv
observations, filesystem notifications, a persistent JSON connection to QML,
and a redesigned visual layer. Their combined effect can be measured. These
measurements do not establish that substituting Rust for Python, while keeping
every algorithm and transport unchanged, would produce the same improvement.

The resident Python control runs the original `Player` logic through a small
stdin adapter. It removes interpreter startup on every action but still reads
files and opens the original mpv IPC connections. Rust also changes those
algorithms. The resident comparison therefore identifies startup costs and a
remaining implementation difference; it cannot attribute that difference
entirely to the programming language.

## Method and limits

The machine has an Intel Core i5-12450H with 12 logical CPUs, Linux
7.2.5-3-omarchy, Python 3.14.7, mpv 0.41.0 and Rust 1.99.0. Its CPU governor
remained `powersave`, with variable clock speeds. Raw files record timestamps,
load averages, CPU frequencies and governors before and after each case.
No build or test suite ran during the final quantitative window. Normal
desktop services remained running.

Every fixture has private XDG directories, a private D-Bus with service
activation disabled, and real mpv processes using `--ao=null`. Music and voice
use the same local 48 kHz WAV; ambience uses the original bundled loops.
Cases contain zero, one, three or eleven actual mpv channels. No installed
plugin settings, playback or runtime files are modified.

Command tests use warm filesystem caches, five status warmups, 50 samples per
operation and seeded randomized operation order. The additional comparison
randomizes backend order on every iteration, while keeping both fixtures
active on separate buses. Use the separate runs for CPU and memory: the
interleaved run deliberately doubles the audio workload. Reported p95 is the
nearest-rank observed percentile, not a statistical confidence bound.

CPU is expressed as a percentage of **one core**. Each steady phase is sampled
for 15 seconds. `/proc` CPU accounting has 0.01-second ticks, so one tick is
about 0.067 percentage points over that interval. A zero observation means
below that resolution. Process CPU includes all threads; recorded voluntary
context-switch counts come from the process leader only. The latter are not
whole-thread-group wakeup counts.

PSS apportions shared pages and is preferable to adding RSS values from many
mpv processes. The report adds per-process median PSS over each phase; raw
RSS, PSS and process identities are also preserved. Measurements exclude
physical audio output latency, remote stream startup, network variability,
GPU frame time and marketplace review time.

## Measured results

### Interleaved command latency

The table reports median / p95 milliseconds, with 50 samples per route and
case. Rust CLI includes process startup; its production stdio route keeps
the client alive. Status requests here are diagnostic operations: the new
QML widget normally receives pushed state instead of polling status.

| Channels | Python CLI status | Rust CLI status | Resident Python status | Rust production stdio status |
| --- | ---: | ---: | ---: | ---: |
| 0 | 98.45 / 212.61 | 7.33 / 18.19 | 3.67 / 7.77 | 0.75 / 2.30 |
| 1 | 141.80 / 227.90 | 16.57 / 26.89 | 3.38 / 11.29 | 0.44 / 1.78 |
| 3 | 164.97 / 273.96 | 15.35 / 24.92 | 4.80 / 14.70 | 0.62 / 2.44 |
| 11 | 142.38 / 260.31 | 17.89 / 26.34 | 3.35 / 5.23 | 0.27 / 0.88 |

At three channels, Python CLI → resident Python reduces median status time
from 164.97 to 4.80 ms. Rust production stdio is 0.62 ms. The first reduction
identifies the large per-command startup cost. The second also includes
Rust's cached state and different IPC/event algorithms; it is not a pure
language comparison. The final three-channel cProfile sample spends 0.061
of 0.071 seconds in import resolution, supporting that startup diagnosis.

Volume and transport results from the same randomized run are below.
Pause/resume is the sum of two commands, with fades disabled. These values
measure command responses; actual fade completion is measured separately.

| Channels / operation | Python CLI | Rust CLI | Resident Python | Rust production stdio |
| --- | ---: | ---: | ---: | ---: |
| 0 / volume | 116.23 / 224.77 | 6.88 / 20.40 | 3.50 / 7.69 | 0.83 / 2.05 |
| 1 / volume | 145.43 / 238.74 | 14.58 / 26.67 | 3.21 / 10.39 | 0.49 / 1.72 |
| 3 / volume | 168.09 / 259.37 | 17.04 / 25.69 | 6.06 / 14.84 | 0.70 / 1.92 |
| 11 / volume | 157.48 / 284.91 | 18.70 / 30.14 | 3.40 / 5.01 | 0.57 / 1.00 |
| 1 / pause + resume | 308.37 / 467.91 | 32.38 / 49.74 | 9.01 / 32.83 | 1.08 / 4.65 |
| 3 / pause + resume | 360.27 / 465.70 | 36.55 / 53.00 | 25.46 / 52.12 | 2.09 / 5.68 |
| 11 / pause + resume | 339.46 / 505.76 | 36.37 / 49.72 | 22.91 / 28.18 | 1.28 / 2.23 |

### Persistent control plane

Python rows add its volume worker and MPRIS service. Rust rows add the
controller and production `--stdio` client, including their shared-page PSS.
The original plugin has no persistent backend while stopped. It still starts
a Python status command every two seconds when its bar widget is loaded.

| Audio channels | Python control CPU, % one core | Rust control + connection CPU, % | Python control PSS, MiB | Rust control + connection PSS, MiB |
| --- | ---: | ---: | ---: | ---: |
| 0 | 0.00 | <0.067 | 0.00 | 4.61 |
| 1 | 2.13 | 0.40 | 29.28 | 4.79 |
| 3 | 2.33 | 0.53 | 29.44 | 4.86 |
| 11 | 2.40 | 0.67 | 29.15 | 5.12 |

At eleven channels this is about 72% less persistent control CPU and 82%
less control PSS. The stopped tradeoff is approximately 4.6 MiB resident
PSS for a ready controller/connection. In the old polling simulation, the
transient status commands alone added 6.96–7.78% of one core across these
cases. The new production connection receives status events without those
periodic CLI launches.

### Complete audio processes

These separate-run totals include all mpv processes and each backend's
control services, without the Rust stdio client. They demonstrate the
remaining decoder cost rather than projecting control-plane savings onto
the whole application.

| Audio channels | Python total CPU, % one core | Rust total CPU, % one core | Python total PSS, MiB | Rust total PSS, MiB |
| --- | ---: | ---: | ---: | ---: |
| 0 | 0.00 | <0.067 | 0.00 | 4.25 |
| 1 | 3.40 | 1.60 | 72.29 | 46.99 |
| 3 | 7.06 | 5.13 | 151.48 | 127.38 |
| 11 | 18.83 | 21.60 | 452.83 | 427.11 |

Whole-audio CPU improvement is mixed: the eleven-channel Rust run used more
CPU despite the cheaper controller. Decoder load and variable host clocks
remain material, and these samples do not justify a universal full-audio
CPU speedup claim. At eleven channels, mpv accounts for approximately
422 MiB of the 427 MiB Rust total. Reducing the number of audio processes
would be a separate mixer/decoder project; this rewrite retains real mpv
playback, media compatibility and cancellation behavior.

To investigate the separate-run CPU reversal, an additional aligned
15-second observation kept both eleven-channel fixtures playing
simultaneously, without commands or adapters. In that shared window,
Python used 23.37% of one core (3.06% control services, 20.31% mpv) and Rust
used 20.64% (0.60% controller, 20.04% mpv). Decoder CPU was approximately
equal; control savings remained. This [paired observation](../perf-results/paired-eleven.json)
does not support a decoder regression, but a single paired window with
twice the audio workload is not a general decoder speedup proof either.
Both observations are retained instead of selecting only the favorable
whole-process total.

### Actual volume application

Each value is median / p95 milliseconds over 20 samples. A single music
volume command is followed by a direct mpv property query until the target
is reached within 0.1. Master volume is already 100%; no extra master command
is included in this table. The original resident adapter returns before its
periodic volume worker applies the value, which is visible in these results.

| Channels | Python CLI → actual mpv | Rust CLI → actual mpv | Resident Python → actual mpv | Rust production stdio → actual mpv |
| --- | ---: | ---: | ---: | ---: |
| 1 | 203.03 / 303.02 | 9.36 / 21.51 | 103.28 / 114.00 | 0.60 / 1.17 |
| 3 | 154.48 / 306.62 | 8.45 / 25.73 | 104.60 / 118.02 | 0.82 / 1.30 |
| 11 | 213.71 / 313.18 | 17.50 / 32.94 | 109.48 / 112.88 | 1.67 / 2.72 |

These are local control-to-mpv latencies with silent output, not audible
speaker latency.

### Ducking and committed fades

Five samples per operation use three actual channels (music 65, voice 20,
rain 25), master 100 and a duck gain of 20%. Duck timing starts at the
fixture's recording/idle state-file write and ends when all volumes reach
their targets within 0.1. No CLI command is in that timed duck path.
Fade timing uses a configured one-second fade in and 0.6-second fade out.

| Actual behavior | Python median / p95, ms | Rust median / p95, ms |
| --- | ---: | ---: |
| Duck down applied | 2304.29 / 2312.59 | 260.97 / 285.32 |
| Duck up applied | 2315.21 / 2327.36 | 266.75 / 281.88 |
| Pause command acknowledged | 152.52 / 171.78 | 23.15 / 28.11 |
| All channels actually paused after fade | 932.44 / 934.45 | 626.54 / 635.02 |
| All channels resumed at target volumes | 1177.28 / 1385.16 | 1034.50 / 1036.46 |

At committed pause every channel reports paused and volume within 0.1 of
zero. The Rust result follows the configured fade duration more closely;
its faster acknowledgment does not bypass the fade. The duck improvement
also changes behavior: the native implementation uses a bounded 0.25-second
envelope rather than the old periodic gradual convergence. It does not
mean Python takes two seconds to perform the same arithmetic.

### Visual-layer CPU

This comparison loads the actual original and redesigned QML in disposable
Quickshell processes with a fixed 478×696 offscreen viewport, the installed
Omarchy UI/theme and the same injected playing state. Each case settles for
two seconds and is measured for 15 seconds. `KeyboardPanel` layer-shell
plumbing is replaced by an Item controlled by `open`; the remaining QML is
unchanged. All QML source hashes and logs are recorded.

| Screen state | Original QML CPU, % one core | Redesigned QML CPU, % one core | Original process PSS, MiB | Redesigned process PSS, MiB |
| --- | ---: | ---: | ---: | ---: |
| Closed | <0.067 | <0.067 | 78.65 | 80.93 |
| Listening, animations enabled | 18.79 | 4.07 | 106.48 | 101.26 |
| Settings | <0.067 | <0.067 | 79.49 | 81.20 |

The active listening scene uses about 78% less process CPU in this offscreen
test. The closed/settings processes use slightly more PSS in the redesign,
while the active scene uses about 5 MiB less. These are complete disposable
Quickshell process footprints, including shared UI infrastructure. There is
no backend, audio or bar widget in this test, so this gain belongs to the
QML/animation redesign, not Rust. It does not measure on-screen GPU/FPS,
input-to-frame latency or the installed shared desktop shell's memory.

## Regressions discovered by measurement

An early functionally passing Rust build consumed about 118% of one core
with no audio. Reading watched VoxType/settings files generated access events,
which triggered more reads. The rejected run is retained as
[idle-loop evidence](../perf-results/rust-native-rejected-idle-loop.json).
The callback now accepts create/modify/remove events, and a real stopped
controller regression checks CPU ticks and an unchanged status-file mtime.
Functional tests alone had not caught the loop.

After that correction, eleven channels still cost about 2.06% of one core in
the controller because ambience progress/metadata were observed despite not
being displayed. [The complete before-trim run](../perf-results/rust-native-before-observation-trim.json)
is retained. Ambience now observes static `audio-params` for initial fade
readiness; the music and voice channels retain progress and metadata updates.
The final integration suite verifies that nature starts and fades correctly.

## Existing desktop observation

The [read-only 20-second observation of the installed Python plugin](../perf-results/live-before.json)
found approximately 3.75% of one core and 12.95 MiB PSS in its volume worker,
plus 0.15% and 17.34 MiB PSS in MPRIS. Its three existing mpv processes had
about 195.84 MiB combined PSS. These live streams and playback states differ
from the controlled fixtures, so they are context rather than a matched
speed comparison. This observation excludes transient command processes.

The desktop's shared Quickshell process used approximately 6.34% CPU and
424.13 MiB PSS during that sample. It hosts the whole shell; those figures
cannot be assigned to Skylofi.

## Verification and raw artifacts

- The pinned original backend suite passed 78 reference tests before the
  rewrite. After the shared fixture/test changes, the current Python reference
  suite again passed all 78 tests in 181.395 seconds.
  [Final reference log](../perf-results/python-tests-final.txt).
  Imported Python unit tests validate the retained reference code.
- The final release passed 50 actual native CLI/daemon integration and QA
  cases in 104.171 seconds. [Full log](../perf-results/rust-tests-final.txt).
  Coverage includes eleven layers, applied fades and ducking, concurrent
  clients, suspended mpv, native MPRIS/reconnection, trusted local HTTPS feeds,
  deep extractor cancellation, decoy-process safety, persistence failures,
  Python-to-Rust migration and executable replacement.
- The native crate passed nine unit tests, formatting and clippy with warnings
  rejected, including partial cancellation failure cleanup, already-exited
  process identities, file-event filtering and ambience observation readiness.
- The QML redesign passed 28 real component checks (panel 8, layout 5,
  dropdown 5, library 7 and widget 3). The three widget checks were repeated
  against the final measured executable and passed. These are separate from
  backend integration.

Primary datasets are [final Python](../perf-results/python-baseline-final.json),
[final Rust](../perf-results/rust-native.json),
[interleaved command comparison](../perf-results/interleaved-compare.json),
[paired eleven-channel observation](../perf-results/paired-eleven.json),
[actual applied duck/fade](../perf-results/applied-behavior.json), and
[offscreen QML comparison](../perf-results/qml-redesign.json).

[Earlier Python](../perf-results/python-baseline.json) and
[preliminary Python](../perf-results/python-baseline-preliminary.json) runs
are preserved for the audit trail. Some earlier phases overlapped toolchain
work or reference tests and are not used for the final result tables.
The [initial native test failures](../perf-results/rust-tests-initial.txt)
and [functionally passing pre-idle-fix run](../perf-results/rust-tests-before-idle-fix.txt)
are retained as development evidence, separate from the final passing log.
Python cProfile summaries are retained for [zero](../perf-results/profile-0.txt),
[one](../perf-results/profile-1.txt), [three](../perf-results/profile-3.txt) and
[eleven](../perf-results/profile-11.txt) channels. Profiled time includes
profiler overhead and is not substituted for command wall-time samples.

## Reproduce

From the repository root, first pin the unchanged Python source and build the
native executable. Building is deliberately separate from measurement:

```sh
mkdir -p /tmp/skylofi-python-baseline
git archive a3b79ad0be4879b34b4e940d1a46ec65865d6144 | tar -x -C /tmp/skylofi-python-baseline
scripts/build-native.sh
scripts/package-native.sh
```

The scripts build outside the watched plugin directory and package the
executable at `bin/linux-x86_64/skylofi`. Run each command sequentially, without
other builds or tests:

```sh
dbus-run-session --config-file tests/dbus-no-activation.conf -- python3 -B tools/perf_baseline.py --source /tmp/skylofi-python-baseline --backend python --samples 50 --seconds 15 --output perf-results/python-baseline-final.json
dbus-run-session --config-file tests/dbus-no-activation.conf -- python3 -B tools/perf_baseline.py --backend rust --native-binary bin/linux-x86_64/skylofi --samples 50 --seconds 15 --output perf-results/rust-native.json
python3 -B tools/perf_compare.py --python-source /tmp/skylofi-python-baseline --native-binary bin/linux-x86_64/skylofi --samples 50 --output perf-results/interleaved-compare.json
python3 -B tools/perf_compare.py --python-source /tmp/skylofi-python-baseline --native-binary bin/linux-x86_64/skylofi --channels 11 --paired-cpu-seconds 15 --samples 50 --output perf-results/paired-eleven.json
dbus-run-session --config-file tests/dbus-no-activation.conf -- python3 -B tools/perf_behavior.py --python-source /tmp/skylofi-python-baseline --native-binary bin/linux-x86_64/skylofi --samples 5 --output perf-results/applied-behavior.json
python3 -B tools/perf_qml.py --python-source /tmp/skylofi-python-baseline --seconds 15 --output perf-results/qml-redesign.json
```

The QML experiment requires the local Omarchy/Quickshell installation.
The final native integration command is:

```sh
env PYTHONPATH=tests LOFI_TEST_BACKEND=rust SKYLOFI_NATIVE="$PWD/bin/linux-x86_64/skylofi" dbus-run-session --config-file tests/dbus-no-activation.conf -- python3 -B -m unittest -v player_test youtube_test.YoutubeIntegrationTest native_test qa_test
```
