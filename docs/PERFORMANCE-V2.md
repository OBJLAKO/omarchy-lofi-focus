# Second design revision: validation and measurements

This report identifies **3.0.0-alpha.2**. The original Python-versus-Rust
comparison remains in [PERFORMANCE.md](PERFORMANCE.md), with its original
alpha.1 executable and source hashes. These new measurements are a regression
smoke check and an interface comparison, not a replacement of that dataset.

## Native controller

The [build identity](../perf-results/native-build-design-v2.json) records the
packaged executable and every native source hash. The executable SHA-256 is
`e2cf9f41a81779bffb06d65dbe8e8969089b391e2e1deaf9180757d7b7cee9ac`.

The [raw smoke run](../perf-results/rust-design-v2-smoke.json) uses real mpv,
`--ao=null`, local WAV music/voice, original bundled nature files, private D-Bus
and temporary settings. Each phase samples for ten seconds; commands have twenty
samples. Test/build/render jobs had finished before measurement. Host load,
frequencies and power policy are recorded; this is not a controlled comparison
against a simultaneously measured Python build.

| Active audio channels | Control CPU, % one core | Controller + client PSS, MiB | Entire audio tree PSS, MiB | Resident volume reply median, ms | Volume applied at mpv median, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 0.00 | 4.62 | 4.62 | 1.84 | — |
| 3 | 0.50 | 4.83 | 124.55 | 1.15 | 1.18 |
| 11 | 0.50 | 4.97 | 427.69 | 0.70 | 0.93 |

The control columns include the production stdio subscription. Reported zero
means no sampled CPU ticks in that ten-second interval, with a 10 ms tick
resolution; it does not mean execution can never consume CPU. Applied-volume
timings observe mpv IPC, not speaker output. CLI startup results vary noticeably
across this run and are preserved rather than interpreted as a language effect.
Audio decoding still dominates memory at eleven channels.

## Interface comparison

The [raw QML comparison](../perf-results/qml-design-v2.json) loads the actual
alpha.1 QML from commit `2d671ab` and final alpha.2 QML into separate disposable
Quickshell processes. Both use the same fixture, host types/theme, playing
status, enabled motion and fixed 478 × 696 px offscreen window. Layer-shell
placement is replaced by a visible Item, with two seconds of settling and ten
seconds of sampling per case. Source hashes and complete logs are retained.

| State | Alpha.1 CPU, % one core | Alpha.2 CPU, % one core | Alpha.1 PSS, MiB | Alpha.2 PSS, MiB |
| --- | ---: | ---: | ---: | ---: |
| Closed | 0.00 | 0.00 | 78.98 | 79.74 |
| Listen | 3.60 | 0.00 | 100.91 | 105.76 |
| Settings | 0.00 | 0.00 | 79.08 | 103.82 |

The new playback mark responds once and settles, replacing the repeated
animation in the first redesign. No steady CPU ticks or voluntary wakeups were
sampled in the new Listen fixture. This benefit belongs to the QML motion
implementation, not the backend language. The stable player and retained page
content have a memory cost: the new Settings fixture uses about 24.7 MiB more
PSS. These are complete isolated-renderer processes; they do not measure GPU,
on-screen FPS, physical input latency or incremental memory in the shared
desktop shell. The separate UI audit reproduces actual panel insets and scale.

## Correctness and scope

- Formatting and Clippy with warnings rejected; ten Rust unit tests.
- [53 native integration/QA cases](../perf-results/rust-tests-design-v2.txt),
  including real offline extraction, seek/resume, live EOF recovery, process-tree
  cancellation, settings migration and MPRIS recovery.
- 25 actual QML component cases and three real Rust/QML transport cases.
- [Independent UI audit](DESIGN-V2-REVIEW.md): 90 interaction cases across six
  variants, with 180 fresh screenshots and a final QML source-hash manifest.

The fixture now waits for the pinned controller process to exit after its
shutdown reply before deleting temporary files. Repeated verification exposed
a race in test cleanup, rather than an assertion failure in playback behavior.

Radio and saved live/unknown sources do not gain seeking from mpv's buffer
duration. Confirmed recordings retain seek, bookmarks and Replay; radio/live EOF
uses recovery. All new application backend/source-policy code is Rust. Legacy
Python application modules remain a comparison reference; Python test and
measurement drivers are not application runtime modules. QML is the required
host presentation layer, and mpv/yt-dlp remain external dependencies.

The [audio-engine evaluation](AUDIO-ENGINE-EVALUATION.md) recommends a measured
Rust nature-mixer prototype as the next resource optimization. It records memory
budgets and adoption criteria; no replacement decoder is implemented or claimed
to be faster in this revision.

## Reproduction

Build and package explicitly before measuring. Archive commit `2d671ab` into
`/tmp/skylofi-design-v1-source` for the interface baseline.

```sh
scripts/build-native.sh
scripts/package-native.sh
dbus-run-session --config-file tests/dbus-no-activation.conf -- python3 -B tools/perf_baseline.py --backend rust --native-binary bin/linux-x86_64/skylofi --build-identity perf-results/native-build-design-v2.json --channels 0 3 11 --samples 20 --seconds 10 --output perf-results/rust-design-v2-smoke.json
python3 -B tools/perf_qml.py --python-source /tmp/skylofi-design-v1-source --baseline-label design_v1_alpha1 --current-label design_v2_alpha2 --seconds 10 --output perf-results/qml-design-v2.json
python3 -B tools/ui_review_v2.py --variant all
```
