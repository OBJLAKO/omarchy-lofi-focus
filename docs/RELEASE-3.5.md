# Skylofi 3.5.0 — Make room for focus

Release date: 8 October 2026. Plugin ID: `sky.lofi`. The tested `3.5` branch is
promoted to `main` with its separate author-only commits and compatible user
preferences. This release adds a personal sound space to radio and saved
YouTube audio.

## Changes

The offline library grows from nine credited recordings to **32 sounds**, with
23 original Rust-generated textures and validated private Ogg/WAV/FLAC/MP3
imports. Up to 16 ambient layers share one Rust/Kira output and bounded streaming
decoders. Online music and optional voices retain mpv playback.

Each source has live Volume, Distance and Coverage controls, quick Nearby,
Distant and Around presets, and an accessible shared positioning map. Room
presets, softness, reflections and echo shape the environment. Coverage creates
stereo diffusion, including for mono material; it is not measured HRTF front/back
localization or head tracking. Living mix gently varies unlocked layers below
their chosen levels. Named scenes remember sources, voice and room settings
while preserving the current master level and playback intent.

All sliders send bounded intermediate updates while dragging and immediately
flush the final value. Stable source-card identity and a permanent scene caption
prevent the panel from jumping on status updates or the first edit. A visible
persistent Solo isolates one active sound without changing saved levels, with a
Back to mix action. Voice is restored for YouTube-backed Radio presets.

## Distribution

The repository includes the executable required by Omarchy's standard clone and
fast-forward update path. Runtime performs no compilation, helper download or
installation hook. The supplied executable is **x86_64 GNU/Linux**, built and
tested on Ubuntu 24.04 in [distribution CI](https://github.com/OBJLAKO/omarchy-lofi-focus/actions/runs/37741826698).
Its compiled input is `012a8e9127daa304a86af87ad0e3028ef3b24c6a`; all native source files, Cargo.toml,
Cargo.lock and toolchain hashes match the final package. The final tag and
marketplace request identify the complete release commit separately.

Executable SHA-256: `4c10096ae47a056c91b281d1232a74eedac100c7fd7c972c3d70570306262342`; size: 7,482,480 bytes.
[Build identity](../bin/BUILD-IDENTITY.json) and [checksums](../bin/SHA256SUMS)
record the actual executable and compiler. PIE, immediate binding, RELRO and a
non-executable stack were checked on this binary. Dynamic requirements remain
ALSA, libgcc, libm, libc and the GNU loader; mandatory glibc reaches 2.34 and
2.39 symbols are weak. Omarchy's Quickshell, session D-Bus and mpv are required;
YouTube also requires yt-dlp and a supported JavaScript runtime such as Deno.
ARM and other platforms require separately tested builds.

Dependency and standard-library notices ship under [native/](native/), and
recordings retain their [individual licenses](../SOUNDS-LICENSES.md). Private
settings, imports, playback sessions and backups are outside this repository.

## Validation

Distribution CI passed formatting, Clippy with warnings denied, **32 native
unit tests**, **68 Rust integrations** and **62 frozen Python regressions**.
The independent [reference/security CI](https://github.com/OBJLAKO/omarchy-lofi-focus/actions/runs/37741826709)
passed **84 Python cases** and its Bandit gate. Tests use isolated D-Bus, local
fixtures and silent/mock audio. They cover source supervision, settings failures,
recovery, decoder acceptance for all 32 sounds, persistent Solo, intermediate
slider commands and stable process identities.

The **same Ubuntu executable** passed all 68 integrations again on Omarchy in
154.133 seconds, plus four real Rust/QML transport checks. Its binary and
source hashes match the packaged identity. The [release validation record](release-3.5-validation.json)
keeps this result separate from the older locally built previews.

The unchanged QML has [live-controls validation](3.5-LIVE-CONTROLS-REVIEW.md):
17 panel-state tests, 10 pointer/layout/key tests, seven library cases,
24 geometry checks and four render variants including compact windows and
150% fonts. [Showcase provenance](showcase/3.5/README.md) records current actual
QML renders with isolated sample state. Historical performance and lifecycle
measurements identify their older executable hashes in
[PERFORMANCE-3.5.md](PERFORMANCE-3.5.md); they are not new benchmarks of this
Ubuntu executable. Listening and long-duration hardware behavior are separate
from the silent automated checks.

## Security and marketplace

The final [local preflight](3.5-marketplace-preflight-release.json) uses current
official marketplace source `92758f8aa9a7a466433a1877cba3e60f66679267`.
Its scanner modules match the previously reviewed policy. The RustSec database
HEAD was rechecked on 8 October and remains
`b8a1a33e246a0a9a3b5f377248c41a503defec74`; Cargo.lock is unchanged since the
[locked advisory comparison](3.5-rustsec-lock-check.json). That report has no
known vulnerability matches and preserves the informational `instant` 0.1.13
unmaintained notice. This is not a new cargo-audit or yanked-package check.
[Initial source-boundary review](3.5-SECURITY-REVIEW.md) and the
[coverage review](3.5-COVERAGE-REVIEW.md) preserve their scope and evidence.

The bundled executable requires explicit marketplace maintainer review. Submit
the existing-listing update with the exact final 40-character `main` SHA and
keep it fixed during review. The new preview and manifest description update
the existing card after promotion. Local preflight, successful CI and a GitHub
release do not constitute marketplace acceptance; its previous snapshot stays
authoritative until the guarded update is approved and deployed.
