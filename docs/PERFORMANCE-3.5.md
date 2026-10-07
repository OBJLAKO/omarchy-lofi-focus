# 3.5 local mixer: resource and lifecycle measurements

The local Rust mixer substantially reduces the measured memory cost of nine
ambient sources. In this run the owned playback tree used **65.46 MiB PSS** for
the native dry mix, compared with **384.01 MiB** for the same nine assets in
separate mpv instances, a reduction of about **83%**. CPU was higher for the
native path; this is a resource smoke check, not a claim that Rust decoding is
faster.

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
```
