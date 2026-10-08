# Skylofi 3.5

A lo-fi radio and nature-sound mixer for **Omarchy**, with a native **Rust**
controller, local audio mixer and a theme-aware QML interface. Choose a soundtrack,
place your ambient layers, save a scene and let its levels drift gently.

[Marketplace](https://omarchyplugins.com/plugin.html?id=sky.lofi) ·
[Install](#install) · [See it in action](#make-it-your-space) ·
[Performance](#measured-with-care) · [Release notes](CHANGELOG.md)

![Skylofi 3 cover: a quiet listening space with the Listen, Mix and Settings interface](docs/showcase/skylofi-v3-cover.png)

## Install

On Omarchy with plugin support:

```sh
omarchy plugin add https://github.com/OBJLAKO/omarchy-lofi-focus.git --enable
```

The command installs the repository's current upstream version. The
[marketplace listing](https://omarchyplugins.com/plugin.html?id=sky.lofi)
has a reviewed 3.0.1 snapshot. This 3.5 development branch needs its own exact-commit
verification before publication; [the previous review](https://github.com/omacom/omarchy-plugin-marketplace/issues/9719)
does not cover new code or binaries.

**Requirements:** Omarchy's plugin-capable Quickshell shell, mpv and session
D-Bus and ALSA (normally routed through Omarchy's PipeWire). YouTube playback additionally needs yt-dlp and a supported JavaScript
runtime, such as Deno. No account or API key is needed; private and restricted
videos are not supported.

The repository includes a tested **x86_64 GNU/Linux** executable. Normal
installation needs no Rust toolchain; the launcher never builds or downloads
code at runtime. Other architectures need an explicit tested build. The plugin
ID stays `sky.lofi`; existing preferences and saved links migrate automatically.

## Make it your space

### Listen

Pick a lo-fi station or save a public YouTube link to your library. Search makes
both easy to find, while playback and overall volume stay within reach across
every tab. Radio stays live; only confirmed recordings expose a timeline,
seeking and saved playback position.

![Listen demo: choose a soundtrack with a persistent playback dock](docs/showcase/listen-demo.gif)

<details>
<summary><strong>Mix — build your own atmosphere</strong></summary>

Balance the soundtrack, an optional voice and your nature sounds independently.
The offline library contains **32 sounds**: nine credited recordings and 23
distinct procedural textures generated in Rust. Up to 16 ambient layers can play
together. Each layer has its own level; **All sounds** adjusts the complete mix.

Save a named scene to remember the soundtrack, voice, layers and acoustic settings.
Applying a scene preserves playback intent and overall volume. **Living mix**
gently varies each unlocked layer independently below its chosen level; zero stays
silent and disabling motion smoothly restores the chosen balance.

Expand a sound card to adjust **Volume**, **Distance** and **Coverage**. Coverage
changes continuously from a focused point through a wide source to a surrounding
stereo texture, including for mono recordings. Try **Nearby**, **Distant** or
**Around** as starting points. Every card has a visible **Solo** button to edit
that active sound alone. Isolation stays on until **Back to mix**, Pause, Stop
or a source/scene change; selecting another card does not end it. Solo never
changes the other saved levels or enabled sounds.

All sliders apply while dragging, using bounded live updates and an immediate
final value on release. Routine status updates preserve the card, mouse grab,
expanded details and scroll position.

Open **Sound space** for a larger shared map: move small source markers left/right
and near/far, with continuous coverage zones. Choose one room preset; muffling,
reflections, echo and acoustic boundaries stay under **Details**. The stereo
diffuser creates an enveloping impression, especially in headphones; it does
not provide measured HRTF front/back localization or head tracking. Existing
scenes migrate their former width into coverage and retain levels and placement.
See the [sound-space guide](docs/SOUND-SPACE.md) for a nearby fire and surrounding
rain recipe.

Import your own Ogg, WAV, FLAC or MP3 recordings into a private library. Source files
are copied, so moving the original does not break a scene. See the
[library and sound provenance](docs/library-3.5.md).

![Mix demo: layer nature sounds and adjust their individual levels](docs/showcase/mix-demo.gif)

</details>

<details>
<summary><strong>Settings — make it comfortable</strong></summary>

Adjust playback fades, how much audio remains while VoxType records, and
interface motion. Normal volume returns during transcription. Motion can be
disabled independently of audio fades, and the panel follows your Omarchy
theme and fonts.

![Settings demo: adjust fades, dictation ducking and interface motion](docs/showcase/settings-demo.gif)

</details>

The clips illustrate the earlier 3.0 interface with controlled sample state. They
show interaction and motion, rather than remote-stream loading times or audio.
The cover is promotional artwork based on interface references.

Four direct lo-fi stations and four Lofi Girl YouTube presets are included.
Voice choices cover talk radio, ATC and publisher-hosted podcasts; availability
depends on the source and network. See [station sources](STATIONS.md) and
[sound credits](SOUNDS-LICENSES.md). Saved YouTube audio takes the foreground
channel and suspends the optional voice; nature layers keep playing.

## Close at hand

| Control | Action |
| --- | --- |
| Left-click the bar icon | Play or pause the remembered mix |
| Right-click | Open the panel |
| Middle-click | Select the next source |
| Scroll over the bar icon | Adjust overall volume by 5% |
| Media keys | Control playback through MPRIS |

Inside the panel, use Tab and keyboard controls; Escape dismisses it. Scrolling
over an unfocused level control scrolls the page without changing volume.
VoxType ducking supports its standard state file and a custom state path in
the default configuration.

## Rust where it helps

The QML interface runs inside Omarchy's Quickshell host and keeps a persistent
local connection to the Rust controller. Rust manages settings, process
supervision, cached IPC state, recovery, the library, fades, dictation ducking,
RSS podcasts and MPRIS. Local ambience uses **one Rust/Kira mixer**, bounded
streaming decoders, shared room reverb and delay, and smoothed layer controls.
mpv handles online music and voice; yt-dlp extracts YouTube streams. The preserved
Python implementation and the explicit mpv ambience mode are legacy regression
references, outside the normal 3.5 runtime path.

The 3.5 preview executable is locally built and validated on this Omarchy system.
The Ubuntu 24.04 workflow includes the new ALSA build dependency and still needs
to run before a distribution release. Matching source, locked dependencies,
checksums and build identity ship with the preview. See
[native distribution](docs/RUST-PUBLISHING.md) and the
[audio-engine evaluation](docs/AUDIO-ENGINE-EVALUATION.md) for the architecture
and runtime requirements.

## Measured with care

The initial 3.5 local-output smoke run measured **65.46 MiB total PSS** with nine
ambient layers, versus **384.01 MiB** with nine separate mpv players. Sixteen
layers with the final coverage effects used **78.71–82.95 MiB** and
**14.99–17.37% of one logical CPU core** in the October 8 short run. Output
paths and host conditions affect CPU comparisons; these are measured samples,
not guarantees. Twenty final rapid stop/start cycles returned to the original
thread and file-descriptor counts after output cleanup. See the
[3.5 measurements and limits](docs/PERFORMANCE-3.5.md) and
[coverage/security review](docs/3.5-COVERAGE-REVIEW.md) and
[live-controls follow-up](docs/3.5-LIVE-CONTROLS-REVIEW.md).

The preserved prototype comparison used real mpv with silent output, local
audio and three active channels:

| Measurement | Previous Python implementation | Rust prototype |
| --- | ---: | ---: |
| Persistent control memory, PSS | 29.4 MiB | 4.9 MiB |
| Volume applied at mpv, median | 154.5 ms via CLI | 0.82 ms via persistent connection |

The earlier **alpha.2** interface smoke run separately recorded **1.18 ms**
median applied volume timing. These are identified alpha builds, not a fresh
benchmark of every release binary. The changes combine Rust, a resident
controller, caching and event handling; they do not isolate language choice.
Timings measure local control, not speaker latency or internet startup, and mpv
was the largest audio-memory cost in that earlier architecture. These historical
figures do not measure the 3.5 local mixer.

Read the [original comparison and raw evidence](docs/PERFORMANCE.md),
[earlier alpha.2 interface measurements](docs/PERFORMANCE-V2.md) and
[independent interaction review](docs/DESIGN-V2-REVIEW.md).
The current interface and playback-motion changes have separate
[3.0.1 polish validation](docs/POLISH-3.0.1.md).

<details>
<summary><strong>Development, storage and CLI</strong></summary>

Building requires Rust 1.99.0, pkg-config and ALSA development headers
(`libasound2-dev` on Ubuntu). Build output stays outside the plugin's watched
directory; the runtime uses the bundled executable or an explicit
`SKYLOFI_NATIVE` developer path.

```sh
scripts/build-native.sh
scripts/package-native.sh
sha256sum --check bin/SHA256SUMS
omarchy plugin validate .
```

The [Rust workflow](.github/workflows/rust-checks.yml) runs format, Clippy,
unit tests and isolated real-mpv integration tests, then records the tested
native artifact. Fixtures use private state and D-Bus with silent audio; mixer
tests also exercise a device-free renderer and allocation tracking.
[Release validation](docs/RELEASE-3.0.md) and the performance reports retain
test results, build identities and reproduction commands.

Preferences and the library live in `$XDG_STATE_HOME/sky.lofi/settings.json`
(normally `~/.local/state/sky.lofi/`). Runtime sockets and logs live in
`$XDG_RUNTIME_DIR/sky.lofi/`.

```sh
./lofi-player toggle
./lofi-player vol master 50
./lofi-player nature noise-rain on
./lofi-player vol noise-rain 35
./lofi-player ducking off
./lofi-player stop
```

Before uninstalling, stop playback and remove `sky.lofi` through Omarchy.
Saved preferences remain outside the plugin directory.

</details>

## Credits

Code is [MIT licensed](LICENSE). Skylofi derives from
[omarchy-lofiatc](https://github.com/dmltallen/omarchy-lofiatc) by dmltallen;
upstream attribution is preserved. Maintained by [OBJLAKO](https://github.com/OBJLAKO).

Nature recordings retain their individual [credits and licenses](SOUNDS-LICENSES.md).
The native bundle includes [dependency notices](docs/native/THIRD-PARTY-NOTICES.txt)
and Rust standard-library [copyright notices](docs/native/RUST-COPYRIGHT-library.html),
[MIT](docs/native/RUST-LICENSE-MIT) and [Apache](docs/native/RUST-LICENSE-APACHE) licenses.
