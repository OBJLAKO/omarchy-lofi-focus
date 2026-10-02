# Skylofi 3.0.1 · interface and project presentation

This patch follows the published 3.0.0 release. It keeps the Rust controller,
QML interface, mpv decoder, plugin ID and settings format. It does not replace
or retag 3.0.0, and it does not attribute architectural improvements solely to
the programming language.

## Slider geometry and keyboard access

The previous focus rectangle had negative margins, painting two pixels beyond
the slider. A clipped tab or adjacent caption could cut off its top edge. The
focus stroke is now inside the hit area. The track also reserves enough inset
for the enlarged thumb at either endpoint, and pointer mapping uses the actual
track origin and width.

Removable mixer rows calculate their compact height from the real caption and
button dimensions. Their remove button stays inside the row. Caption-to-track
spacing is explicit in Settings and finite-recording transport. On a very short
window with 150% fonts, a complete row can exceed the viewport: keyboard focus
scrolls to the actual slider or remove button instead of the whole row.

The focused geometry fixture has 24 cases across normal, 125%, 150% and compact
150% layouts. Restoring the old negative focus margin fails all five normal
cases. The component suite has 25 cases; the independent interaction review
has 90 cases across six layouts, including light and compact variants. Their
final source identities, results and screenshots are in [polish-review/](polish-review/).

## Playback motion

Three small predetermined stems provide ongoing playback feedback, at eight
updates per second. They are a status motif, not an audio spectrum. Only a
playing foreground, voice or nature channel with nonzero channel and overall
volume activates it. Connecting or retrying alone does not imply audible
playback. Pause, mute, hidden parent/window, minimized windows and either
motion preference stop its timer; a static playback mark remains available.
Existing short control, page and disclosure transitions remain local.

Six direct motif tests and seven actual-bar state tests cover continuing
updates, the rate bound, source state, preferences and visibility. The panel's
independent interaction suite additionally checks its playback mark.

The [motion measurement](../perf-results/playback-motion.json) compares the
actual panel and bar against the same interface with only playback-indicator
motion disabled. General interface motion stays enabled. Each case samples
the isolated software-rendered Quickshell process for twelve seconds after
settling. It excludes Rust, mpv, audio/GPU costs and shared desktop-shell memory.
CPU percentages refer to one logical core; an unchanged tick count is below
the approximately 0.083% sampling resolution, not proof of absolute zero work.
PSS is a renderer measurement, not a language-memory comparison.

| Isolated interface | CPU, one core | Median PSS |
| --- | ---: | ---: |
| Panel and bar, static playback mark | <0.083% | 116.93 MiB |
| Panel and bar, ongoing playback mark | 0.67% | 114.81 MiB |
| Bar only, static playback mark | <0.083% | 90.72 MiB |
| Bar only, ongoing playback mark | 0.50% | 90.83 MiB |
| All hidden | <0.083% | 91.88 MiB |

The cases use separate software-rendered processes; allocation variance and
renderer caches prevent a stable incremental-memory conclusion. The lower panel
PSS in the ongoing case is not evidence of a memory improvement. Both hidden
counters remained unchanged. Source hashes
in the raw report match the final QML reviewed and recorded for this patch.

Reproduce without simultaneous GUI fixtures or recordings:

```sh
python3 tools/perf_playback_motion.py --help
python3 tools/ui_review_v2.py --variant all --output docs/polish-review
python3 tests/slider_geometry_test.py
python3 tests/playback_wave_test.py
python3 tests/bar_motion_test.py
```

## Presentation and distribution

The README presents Listen first, with optional Mix and Settings walkthroughs,
an installation command, direct marketplace destination and explicit runtime
architecture. GIFs record actual final QML controls with private sample state;
they do not record user data or claim network/audio latency. The generated
launch cover is artwork based on interface references. Asset provenance and
reproduction are in [SHOWCASE.md](SHOWCASE.md) and [showcase/](showcase/).

The repository description, homepage and ten relevant topics identify Omarchy,
Rust/QML, radio, YouTube, ambient mixing and VoxType. They make the project
context clear without promising search rankings or stars. GitHub's separate
social-preview upload needs its supported Settings UI; a suitable JPEG export
is included even when that UI is unavailable to the editing session.

The patch keeps the explicit CI build and bundled x86_64 GNU/Linux executable.
Its exact compiler, source hashes, build input and binary checksum are recorded
in [BUILD-IDENTITY.json](../bin/BUILD-IDENTITY.json). Final packaging can follow
the CI source commit only if those native source hashes match. Marketplace
publication remains an exact-commit maintainer action; an advisory local scan
and a submitted request do not constitute approval.

The [3.0.1 distribution CI](https://github.com/OBJLAKO/omarchy-lofi-focus/actions/runs/37043554386)
passed format/Clippy, ten Rust unit cases, 54 native integration/QA cases and
the frozen Python reference suite. Its compiled source input is
`a82ca387719811346ea3e3750a1ff71641a3e76d`. The packaged executable SHA-256 is
`b2c8791453774f0e02ffb399e230e883f009467c8adbedc31a7eaf424ef49e66`.
Native source-file hashes match the final repository files.

The same distributed executable has [54 silent integration/QA cases on Omarchy](../perf-results/release-3.0.1-native-tests.txt)
and [three actual Rust/QML transport cases](../perf-results/release-3.0.1-widget-tests.txt).
The [local advisory preflight](../perf-results/marketplace-3.0.1.json) records
zero findings and the bundled-executable capability requiring maintainer review.
It uses official scanner commit `b13d4ffd69a50f44be5d0e563e4eecb4032df7aa`;
the complete scanner scripts tree matches marketplace `main` at
`c556f76d0006a38e168513c66835d6d5c37e3319`.
