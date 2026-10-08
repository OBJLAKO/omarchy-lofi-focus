# 3.5 local mixer: resource and lifecycle measurements

The local Rust mixer substantially reduces the measured memory cost of nine
ambient sources. In this run the owned playback tree used **65.46 MiB PSS** for
the native dry mix, compared with **384.01 MiB** for the same nine assets in
separate mpv instances, a reduction of about **83%**. CPU was higher for the
native path; this is a resource smoke check, not a claim that Rust decoding is
faster.

## Final coverage revision — October 8

The [final coverage run](perf/coverage-3.5.json) uses executable
`c12b04d1929c0d67df1e3303e8c54e3ceeaf4cc616f3f11b9e39ac6edfac0607`,
after the stable-field bypass and bounded silent diffusion tail optimization.
Sixteen wet layers use the settings below except that original stereo width
is 100%; coverage is the variable. Each playing and paused phase samples eight
seconds. The same private, physically silent CPAL/MPV-null setup is used.

| Coverage | Phase | Entire owned tree CPU, % one core | Entire owned tree PSS, MiB |
| --- | --- | ---: | ---: |
| 0, point | Playing | 14.99 | 78.71 |
| 50, wide | Playing | 17.37 | 80.95 |
| 100, surrounding | Playing | 16.87 | 82.95 |
| 100, surrounding | Paused | 7.99 | 83.17 |

The four short delay lines reserve 64 KiB per reusable slot (1 MiB total for
sixteen). Point and centered default stereo bypass unused diffusion. Exact-zero
input retains the short diffuse tail for at most 750 ms, then clears its existing
buffers once and skips that processing. Shared room effects and output stay
active in Pause; this change does not promise zero paused CPU.

Twenty final rapid cycles each returned the same 100 ms snapshot: 15 threads,
38 FDs, one reusable output and no decoder workers. Snapshot PSS went from
15.72 to 16.05 MiB with small warming steps, then stayed at 16.05 MiB for the
last six cycles. Settled state returned to exactly **10 threads / 15 FDs /
zero outputs / zero decoders**, matching baseline. It settled 0.93 seconds
after the last rapid snapshot. Final stopped PSS was 9.88 MiB versus 12.18 MiB
before cycling. This establishes cleanup of the tested path over 20 cycles,
not long-term leak freedom or subjective audio quality.

Earlier October 8 measurements are retained as
[pre-optimization coverage](perf/coverage-3.5-initial.json) and
[the earlier old-field baseline](perf/coverage-3.5-baseline.json). Their old
binary used 27.35% of one core while playing, compared with the 10.90% historical
wet sample below. Host activity, scheduling and output conditions change across
runs, so the historical table is not an interchangeable baseline for the new
effects. All reports retain their actual binary hashes and samples.

The [immediately repeated old-field baseline](perf/coverage-3.5-baseline-final.json)
used the previously bundled `414fdc4a…` executable with the same sixteen wet
layers and width 100, omitting the unsupported coverage command. It measured
24.36% / 79.67 MiB while playing and 12.12% / 79.91 MiB paused. This adjacent
comparison supports the practical bypass change; short sequential samples
cannot isolate all scheduler/device variation or guarantee those CPU reductions
on another host. The earlier historical 10.90% value remains separate.

## Method and executable identity

[The initial raw run](perf/space-3.5.json) samples each phase for ten seconds on
an Intel Core i5-12450H with twelve logical CPUs. It uses the full 32-sound
catalog and the first 0/1/9/16 assets, private XDG state and command sockets, and
a private D-Bus without service activation. Radio URLs become local silence;
Voice, fades and Wander are off. Master volume is zero before audio starts, so
the real local output is physically silent and existing user playback/settings
are untouched. The installed plugin is never invoked or modified.

The native mixer connects through real CPAL/ALSA to the host PipeWire service.
The legacy comparison uses real mpv with `--ao=null`. These output paths differ,
so CPU totals are not an identical-device decoder benchmark. One main mpv
playing local silence is present in every playing case. Totals include that
process, the controller, and all fixture-owned ambient mpv processes; they
exclude the measuring process and private D-Bus. `/proc` samples are taken every
0.5 seconds. CPU percentages use one logical core as 100%; a reported zero means
no sampled CPU ticks, with 10 ms accounting resolution.

The initial executable SHA-256 is
`f3115227a0a4f480af8bbeb8fb432fe5fc78ae805665e963a89807c9f3ee7a13`.
It predates the final 600 ms output reuse window and the correction for turning
fades off during a fade. Both changes leave the measured steady playing phases
unchanged. The [final lifecycle run](perf/space-3.5-lifecycle.json) uses
`414fdc4abd8ca7ff487233b3e7b35422679fdc5952d1ac0200f15049d28ecdda`
and records every native source hash. These are exact measurement identities;
they are not an attestation for a subsequently rebuilt distribution.

## Playing cost

Dry means zero distance, reflections, echo, softness and room reflections, with
centered full-width stereo. Wet uses distance 35%, layer reflections 70%, echo
20%, softness 25%, alternating pan ±40%, width 80%, and room reflections 65%.
These settings and all raw process samples are preserved in the JSON.

| Local layers | Effects | Controller CPU, % one core | Controller PSS, MiB | Entire owned tree CPU, % one core | Entire owned tree PSS, MiB |
| --- | --- | ---: | ---: | ---: | ---: |
| 0 | Dry | 0.20 | 5.04 | 0.70 | 44.38 |
| 1 | Dry | 4.90 | 9.92 | 5.40 | 51.25 |
| 9 | Dry | 8.10 | 24.00 | 8.60 | 65.46 |
| 16 | Dry | 10.10 | 35.64 | 10.60 | 75.85 |
| 0 | Wet settings | 0.20 | 10.92 | 0.50 | 49.25 |
| 1 | Wet | 4.40 | 14.42 | 4.80 | 54.64 |
| 9 | Wet | 7.80 | 25.13 | 8.30 | 64.29 |
| 16 | Wet | 10.50 | 37.07 | 10.90 | 79.72 |
| 9 | Legacy mpv, dry | 0.20 | 5.29 | 6.29 | 384.01 |

The second zero-layer phase follows the larger mixes; its higher memory is a
warmed process observation with zero local sources. The native
controller PSS column includes its audio output, decoder workers and DSP. The
legacy controller column excludes the nine separate decoders, making the
complete owned-tree total the useful memory comparison. No native phase
launched an ambient mpv process.

The final binary repeated nine wet layers at **7.90% controller CPU / 22.91 MiB
controller PSS**, and **8.40% / 64.31 MiB** for the entire owned tree. Pausing the
same mix used **5.10% controller CPU / 23.10 MiB**; all nine decoder workers park,
but the output and shared effects remain active. Reducing paused DSP cost is a
remaining efficiency opportunity. These short runs do not measure audible
quality, physical output latency, underruns, suspend/resume or unplug recovery.

## Output cleanup and rapid reuse

The first run exposed asynchronous output teardown in Kira: its CPAL backend
marks a stream for destruction, and the stream-manager worker checks that flag
every 500 ms. A snapshot taken only 100 ms after Stop therefore observes a
closing output. Before the reuse window, rapid cycles briefly left four such
outputs waiting for that timer. The original raw report retains these
observations rather than presenting them as completed cleanup.

The final controller cancels/joins every decoder and silences the manager
immediately through `clear()`. It retains the empty muted output for 600 ms,
reusing it when audio resumes during that period. After the grace interval it
drops the manager; Kira performs its asynchronous device cleanup. Shutdown
force-drops the output without the reuse interval. The combined normal cleanup
window is approximately 600 ms plus Kira's next 500 ms check; audio silence does
not wait for that resource cleanup.

Twenty rapid cycles each started playback, paused, removed the last source,
re-added it while paused, resumed, and stopped. Every 100 ms stopped snapshot
showed **one reusable output, 15 controller threads, 38 FDs, and zero decoder
threads**. PSS settled near **13.07 MiB** from cycle seven through twenty, rather
than continuing to increase with each toggle. After the final output closed,
the controller returned to exactly **10 threads and 15 FDs**, matching the
warmed stopped baseline, with no output or decoder threads. Observed settling
took about **0.94 seconds** after the last rapid-cycle snapshot. Final stopped
PSS was **8.41 MiB**, compared with **9.17 MiB** before those cycles.

This bounded local stress check establishes successful cleanup for the tested
path. It is not a long soak test or a guarantee that every driver or codec can
never leak. Unit tests additionally cover sixteen-layer limits, two shared
effect buses, paused worker cancellation, output reuse, all nine original
Vorbis files, corrupt import rejection, and zero allocator activity in audited
render, parameter-update and source-retirement paths.

## Reproduction

Build a release executable first, with ALSA development headers available.
The harness never builds or installs the plugin itself. The real-output
measurement needs access to the existing local audio-service socket.

```sh
python3 -B tools/perf_space.py --native-binary /path/to/skylofi --seconds 10 --cycles 20 --output docs/perf/space-3.5.json
python3 -B tools/perf_space.py --native-binary /path/to/skylofi --seconds 10 --cycles 20 --lifecycle-only --output docs/perf/space-3.5-lifecycle.json
python3 -B tools/perf_coverage.py --native-binary /path/to/final-skylofi --seconds 8 --cycles 20 --output docs/perf/coverage-3.5.json
python3 -B tools/perf_coverage.py --baseline-only --native-binary /path/to/previous-3.5-skylofi --seconds 8 --output docs/perf/coverage-3.5-baseline-final.json
```
