# Skylofi 3.0.0

Release date: 2 October 2026. The marketplace plugin ID remains `sky.lofi`.
This release promotes the tested `rustTest` redesign into `main`.

## Changes

The application controller is now Rust: settings and migration, process
supervision, source classification, local IPC, RSS resolution, playback fades,
dictation ducking and MPRIS. QML remains the Omarchy bar/panel interface. mpv
decodes audio; optional YouTube playback uses the installed yt-dlp and its
supported JavaScript runtime. Existing Python application code is retained only
as a comparison/regression reference, outside the normal runtime path.

Listen, Mix and Settings use stable navigation and a persistent compact player.
Forms retain their labels, dropdowns stay inside the panel, keyboard focus
remains visible and an unfocused wheel scrolls without adjusting a sound level.
Local motion follows the interface preference and the playback mark settles
after one short response. Radio/live sources do not expose recording transport;
verified recordings retain seeking, saved position and Replay.

## Distribution

The release ships `bin/linux-x86_64/skylofi` inside the repository, as required by
Omarchy's normal clone/update installation path. There is no runtime compiler,
downloaded helper or installation hook. The distributable executable is built
by the read-only Rust CI workflow on Ubuntu 24.04, after format/lint/unit and
silent integration checks. `bin/BUILD-IDENTITY.json` records its compiler,
workflow run, compiled source commit, exact binary SHA-256 and native source
hashes; `bin/SHA256SUMS` independently checks the packaged executable.

The source-commit field identifies the CI build input. A later packaging commit
may add this tested executable and release evidence; the recorded native source
hashes must still match that release's files. The release tag and marketplace
request identify the final complete repository commit separately.

The supplied executable is **x86_64 GNU/Linux**, dynamically linked to the GNU
loader, libc (required symbols through glibc 2.34) and libgcc. Newer weak symbols
are optional. It is not an ARM or static build. Other architectures
require an explicit tested source build and are not covered by this binary.
Omarchy's Quickshell, mpv and session D-Bus are required; YouTube is optional and
also needs yt-dlp plus a supported JavaScript runtime such as Deno.

All locked Rust dependency notices and matching standard-library notices live
under [native/](native/). Bundled nature recordings retain their separate
[sound credits and licenses](../SOUNDS-LICENSES.md).

## Migration and validation

The ID, preference location and saved-library format remain compatible. The
Rust controller migrates existing settings and replaces legacy controller
services through the tested handoff. The bundled command never invokes the
legacy Python backend unless a developer explicitly selects it.

The release validation covers format/Clippy, ten Rust unit cases, 53 native
integration/QA cases and real Rust/QML transport. The unchanged QML snapshot has
25 component cases and [90 rendered interaction cases across six variants](DESIGN-V2-REVIEW.md),
including custom fonts, compact windows, light palette and reduced motion.
The marketplace's exact-commit static check and native-binary maintainer review
remain separate from these tests.

The [distribution CI run](https://github.com/OBJLAKO/omarchy-lofi-focus/actions/runs/37033064212)
passed all build, native and frozen Python-reference checks. Its exact packaged
executable was then checked on Omarchy with [53 silent integration/QA cases](../perf-results/release-native-tests.txt)
and [three real Rust/QML transport cases](../perf-results/release-widget-tests.txt).
The reviewed QML source hashes still match. The final
[local marketplace preflight](../perf-results/marketplace-release.json) has zero
findings and one review-required capability: the bundled executable.

The [original performance comparison](PERFORMANCE.md) and
[final design measurements](PERFORMANCE-V2.md) preserve their measured alpha
build identities. The stable release changes the package version and
distribution build, so those timings are historical evidence rather than a
claim that a new release binary was measured with the same numbers.

## Marketplace update

Submit one update request for the existing listing with the final `main` SHA.
The bundled executable requires explicit maintainer review under the current
marketplace policy. A local advisory scan is included in the release evidence;
it is not marketplace verification. Until the maintainer completes the guarded
publication workflow, the previous listed snapshot remains authoritative.
