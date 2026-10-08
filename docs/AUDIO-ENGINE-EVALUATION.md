# Audio engine evaluation

Skylofi 3.5 implements a native Rust mixer for local ambience. Kira 0.12.5
owns one output through CPAL 0.18.2; Symphonia 0.6.1 decodes enabled local
files in cancellable workers and rtrb 0.4.0 carries PCM through bounded queues.
Network radio, podcasts and YouTube continue to use mpv, with yt-dlp for
YouTube extraction. The installed system mpv is not reconfigured.

## Implemented 3.5 local path

The bundled library contains **32 offline sounds**, with private local imports
available separately. The mixer supports **16 active local layers**, sixteen
reusable source tracks and two shared wet-only buses for reverb and echo.
Distance affects gain and filtering; each layer also has position, coverage, width,
softness, reflections and echo controls. Parameters are finite, bounded and
smoothed over 45 ms; the final output guard removes nonfinite frames and
attenuates peaks above 0.98.

The coverage refinement adds four preallocated short all-pass lines per reusable
slot (64 KiB per slot, 1 MiB for sixteen), spreading mono as well as stereo input
without extra decoder workers or DSP dependencies. Point/Wide/Surrounding are
continuous stereo diffusion settings, independent of distance. A convex mix
avoids correlated low-frequency gain increases; the surrounding setting is not
measured HRTF front/back audio. Settled point/default-stereo settings bypass
unused diffusion; true-zero input retires its short tail after 750 ms without
allocating. See the [guide](SOUND-SPACE.md) and
[scoped review](3.5-COVERAGE-REVIEW.md) for behavior and final checks.

Each active decoder has a fixed **16,384-frame** stereo queue: about 0.37 seconds
at 44.1 kHz and **about 2 MiB of queue storage at the 16-layer limit**. This excludes
codec state, decoded packet scratch, tracks, effects and the system output.
Clip duration does not increase queue capacity. Only active sounds own decoders,
Pause suspends decoder production and silences the output. Clearing a stopped
or empty mix cancels all decoder workers; the controller retains one silent
output for a 600 ms idle grace so a quick restart can reuse it, then drops that
output. Kira's CPAL stream manager checks pending destruction every 500 ms;
device teardown completes asynchronously after the drop. The measured final
twenty-cycle run returned thread/FD counts to the stopped baseline without
decoder threads. File I/O and decoding stay outside the render callback.

The implementation is in [audio.rs](../native/src/audio.rs), with scene and slow
level movement in [room.rs](../native/src/room.rs). The
[library inventory](library-3.5-inventory.json) records measured asset formats,
levels and provenance. The [3.5 performance report](PERFORMANCE-3.5.md) records
CPU/PSS and lifetime measurements from the implemented mixer; the older values
below do not describe this path. Unit and silent-device checks cannot establish
physical output latency, underruns on every device, or listening comfort.

## Historical evaluation before the 3.5 mixer

The following evaluation describes the alpha.1/3.0 controller and its nine
local layers, which still ran in separate mpv processes. Its measurements led
to the local mixer work above. Alternative-library comparisons and memory
budgets below are historical planning evidence, not measurements or adoption
claims for the current 3.5 implementation.

## What the earlier measurements showed

The alpha.1 [controlled comparisons](PERFORMANCE.md) already reduced applied
three-channel volume latency to a median 0.82 ms through the resident Rust
connection. Removing JSON IPC therefore has limited room to improve this
particular interaction. It does not remove provider response time, extraction,
connection setup or the buffering needed for an unreliable network.

In the eleven-channel fixture, the Rust daemon and ten additional mpv players
used about 427 MiB combined PSS; mpv accounted for about 422 MiB. That identifies
audio instances as the next memory target. It does not establish that replacing
their decoders with Rust will reduce CPU. The paired measurement found nearly
equal decoder CPU with the old and new controllers.

## Practical alternatives

| Approach | Potential benefit | Cost and limitation | Historical decision |
| --- | --- | --- | --- |
| Rust controller + mpv processes | Current tested radio/YouTube/seek/recovery support and process isolation | Each active local layer adds an audio instance | Keep for the current design revision |
| Rust + embedded libmpv | Removes process/socket boundaries; may share some resources between handles | Still uses mpv's decoding stack; instance state and buffering remain; a crash affects its host process | Benchmark before adopting |
| Rust + Rodio/Symphonia for local nature | One output mixer, no per-layer external process, bounded streaming decode | Must implement seamless loops, gains, fade/duck composition and output recovery | Best next prototype |
| Rust + Rodio/Symphonia for every source | Rust-owned decoding and mixing | Additional HTTP/ICY/HLS/DASH, live clock, resampling, reconnect and extractor integration work; codec support must match real streams | Not a direct replacement today |
| Rust + GStreamer | Existing adaptive streaming and synchronized mixing pipeline | Adds a native framework/plugin dependency; no measured resource improvement here | Consider if network pipeline requirements expand |

mpv officially recommends libmpv for embedding an independent application. It is
an API to the same player mechanisms, rather than a different decoder. Any
memory benefit from sharing processes must be measured on the complete mix;
counting fewer PIDs is insufficient. See the [official embedding documentation](https://github.com/mpv-player/mpv/blob/master/DOCS/man/libmpv.rst).

Rodio supplies a mixer and configurable audio output. Its documented default
output buffer is 100 ms, so switching to it does not itself guarantee lower
audible latency. A small buffer needs device-specific underrun testing. See the
[Rodio output documentation](https://docs.rs/rodio/0.22.2/rodio/stream/index.html).

Symphonia provides demuxing, tags and audio decoding. Its current codec table
also records incomplete HE-AAC/HE-AACv2 and Opus support in the native decoders.
Its own performance statement is codec-dependent, not a guarantee that Rust
decoding is faster than FFmpeg. Network radio formats must be checked against
that table; optional native adapters would also change dependencies. See the
[official Symphonia repository](https://github.com/pdeljanov/Symphonia).

GStreamer's adaptive demuxers manage HLS/DASH downloads, stream timing and
buffering; its audiomixer synchronizes and combines raw inputs. This is a mature
alternative when those features are needed, with additional deployment work.
See [adaptive demuxer design](https://gstreamer.freedesktop.org/documentation/additional/design/adaptive-demuxer.html)
and [audiomixer](https://gstreamer.freedesktop.org/documentation/audiomixer/audiomixer.html).

## Local mixer memory budget

All nine bundled assets are stereo Vorbis at 44.1 kHz. Their compressed size is
13.0 MiB, but decoding and retaining every complete loop as float32 would require
about **239.5 MiB**. That would consume much of the memory we are trying to save.

A two-second float32 queue for each of the nine layers is approximately
**6.06 MiB total**, before decoder state, resampling and output buffers. These
numbers are planning estimates computed from actual file durations and formats,
not measurements of an implemented Rust mixer. Raw inputs are recorded in
[audio-assets-v2.json](../perf-results/audio-assets-v2.json).

The prototype should stream/decode enabled loops through bounded queues, mix
into one output, and open no decoder or audio device while stopped. Decode only
enabled layers; pause without accumulating samples. Use a short controlled
crossfade at loop boundaries if the source itself clicks. Fades, per-layer
levels, master volume and dictation gain must remain independent and compose
without clipping or unexpected loudness.

## Adoption criteria

Compare the prototype with the current implementation using identical assets,
0/1/3/9 local layers, the same output device/rate/buffer, and both silent and
real-device runs. Record full-process CPU/PSS, decoder allocations, startup and
applied gain times, callback underruns, and paused/stopped cost. Include loop
boundaries, suspend/resume, unplugged output, dictation, rapid removal and
unexpected stream failure. A memory win must not conceal unstable audio or a
larger steady CPU cost.

Keep the network player behind the existing Rust channel interface while doing
this comparison. A successful local mixer can reduce the many-player cost
without first rebuilding YouTube extraction, live-radio timing and network
recovery. An all-source replacement should follow only after its own codec,
streaming and reliability tests pass.

## Rust-owned network source capabilities

The 3.0 implementation added a bounded Rust proxy around the yt-dlp invocation;
3.5 retains it.
It runs extraction once, forwards the original JSON to mpv, and reports only
the source kind to the matching controller generation. Live and unknown sources
never gain a seek timeline from a decoder's growing buffer duration. The proxy
retains safe process-tree cancellation and does not add another Python or Lua
application module.

The proxy is needed because mpv's normal single-track extraction path does not
always put `is_live` in media metadata, and older supported mpv versions do not
expose the newer extraction-result property. This was verified with a real
silent mpv fixture and the official [0.41 hook](https://github.com/mpv-player/mpv/blob/v0.41.0/player/lua/ytdl_hook.lua)
and [0.37 hook](https://github.com/mpv-player/mpv/blob/v0.37.0/player/lua/ytdl_hook.lua).

Legacy Python application code remains a frozen comparison reference; test
tooling is separate from the application backend. The application controller,
feed resolver, source policy, supervision, settings and media integration are
implemented in Rust. QML remains the host-required presentation layer; mpv and
yt-dlp remain external playback/provider dependencies.
