# Native Rust and Omarchy publication

Research date: 2026-10-02. Release policy rechecked against official marketplace
source `b13d4ffd69a50f44be5d0e563e4eecb4032df7aa`; historical experimental scans
used `34cb24a8c543746065982c568e3929c3a0bb9e07`.

The Omarchy shell loads the plugin's QML entry point. QML remains the interface;
Rust can implement an external controller reached through local IPC. This also
keeps native controller failures outside the shared desktop shell. A Qt extension
implemented with [CXX-Qt](https://github.com/KDAB/cxx-qt) is technically possible,
but adds Qt build and loader compatibility obligations without solving this
plugin's dominant process-startup overhead. A standalone Rust UI would require
changing the native bar/panel integration.

The recommended layout is QML → persistent JSON-lines client → private Unix
socket → Rust daemon → persistent mpv IPC. mpv remains responsible for decoding,
streaming and the audio output; yt-dlp remains the YouTube extractor. The
[mpv IPC reference](https://mpv.io/manual/stable/#json-ipc) documents property
subscriptions and requires keeping their connection open.

## Distribution and review

Omarchy installs a repository by cloning it and validates its manifest; its
update command performs a fast-forward update. The installed command sources
were inspected. Neither action builds Rust or runs a plugin installation hook.
Consequently a source-only repository needs an explicit build/setup step, or a
ready executable must accompany the QML. Release assets alone are not obtained
by the ordinary clone command.

For distribution, build explicitly, then bundle `bin/linux-x86_64/skylofi` with
the source and a checksum file. The runtime performs no downloads or compilation.
A release build made on a compatible Linux runner is preferable to a binary
linked against a developer machine's newer libc. Document architecture and
runtime library requirements; add an ARM build only after it has been tested.

The supplied bundle is an x86_64 GNU/Linux executable, dynamically linked
to `libc.so.6`, `libgcc_s.so.1` and the GNU loader. Its required versioned glibc
symbols reach 2.34; newer weak symbols are optional. This is not a static or
cross-platform binary. Local validation uses this Omarchy machine; the Ubuntu
24.04 CI build is a separate distribution compatibility check.

The [marketplace policy](https://github.com/omacom/omarchy-plugin-marketplace/blob/b13d4ffd69a50f44be5d0e563e4eecb4032df7aa/SECURITY.md)
does not categorically prohibit Rust. Bundled executable files are classified as
`bundled-executable-binary`, requiring maintainer review. A build involving remote
source can also require review. Acceptance is a maintainer decision. Preserve
complete source, locked dependencies, explicit build instructions and licenses.
Checksum files aid reproducibility; they are not proof of marketplace approval.

`docs/native/THIRD-PARTY-NOTICES.txt` collects the original license and notice
texts from the locked Linux dependency graph; Rust standard-library notices
are stored beside it. Regenerate dependency notices with
`python3 tools/native-notices.py` after changing the lockfile, and retain the
matching standard-library license/copyright files when changing the toolchain.

## Updating the existing listing

Follow the official [verification and update workflow](https://github.com/omacom/omarchy-plugin-marketplace/blob/b13d4ffd69a50f44be5d0e563e4eecb4032df7aa/VERIFICATION.md):

1. Complete native regressions, UI review and controlled Python/Rust measurements.
2. Finalize a release commit, including the intended distributable executable,
   matching source, preview, README, manifest version and license information.
3. For the existing `sky.lofi` listing, open the Plugin verification form and
   choose **Verify and publish a newer upstream commit**. Supply the repository,
   plugin ID and exact 40-character HEAD SHA.
4. The marketplace checks that commit. Its maintainer reviews the native binary
   capability and applies `approved-and-verified` after the report is available.

Keep the release commit fixed during review. A later commit needs fresh evidence.
An experiment branch, a tag or passing local tests does not publish the update.
No marketplace update is performed by this branch's CI.

## Build and evidence

The native workflow pins Rust 1.99.0 and the checkout/upload actions, uses read-only
repository permissions, builds with `--locked --release`, runs format/lint/unit
and silent real-mpv integration checks, and checks the bundle checksum. Its
tested native artifact includes source/binary identity for release packaging. Build
output is outside the plugin directory. Use `scripts/build-native.sh` for a local
build and `scripts/package-native.sh` for an explicit bundle.
Explicit packaging removes an older CI identity; the CI workflow writes a new
identity after its tested build. A local rebuild must not retain another
executable's provenance report.

The performance report must distinguish command acknowledgement from the moment
audio changes, and distinguish the Rust controller from mpv and the shared
Quickshell host. A resident Python adapter measures the architectural benefit
separately. Network/provider latency and first-time compilation are separate
measurements, not evidence of controller speed.
