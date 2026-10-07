# Skylofi 3.5 offline library

The catalog grows from nine recordings to 32 offline layers: the original nine
files remain unchanged, and 23 original synthesized textures provide distinct
rain, air, water, fire, mechanical and noise variants. The new tracks are
identified as synthesized in their catalog descriptions and Ogg metadata.
They are not marketed as field recordings or recordings of actual vehicles.

| Family | Available layers |
| --- | --- |
| Rain | Rain, Thunderstorm, Tent rain, Soft drizzle, Window rain, Rain on a roof, Deep downpour |
| Wind | Wind, Wind in leaves, Wind through pines, Winter wind |
| Water | Ocean waves, Forest stream, Wide river, Waterfall, Harbour water, Scattered water drops |
| Fire | Fireplace, Campfire, Glowing embers |
| Forest | Morning birds |
| Night | Night crickets |
| Home | Desk fan, Soft ventilation |
| Travel | Night train, Air cabin |
| Textures | Brown noise, Pink noise, White noise, Tape air, Vinyl texture, Soft drone |

Existing source IDs remain stable. Each ambience entry includes `family`,
`tags` and `origin` metadata; all stay in the existing `ambience` category.
Scenes can therefore keep their layer IDs across this library expansion.

## Personal sounds

The native library also accepts explicitly selected local Ogg, WAV, FLAC and
MP3 files. An import makes a private copy under the plugin's state directory,
so moving the source later does not break a scene. Supported audio is checked
before the entry becomes available. The personal library allows 24 files,
64 MiB per file and 512 MiB total; these are separate from the 32 bundled
layers. Removing an imported sound affects that private copy and its layer
selection, rather than deleting the user's source recording.

The audio output supports up to 16 simultaneous local layers. The full catalog
is available for selection, while streaming queues keep playback memory
independent of clip duration. Personal audio stays local and retains its own
rights; importing it does not apply the bundled sounds' CC0 license to it.

## Sound preparation

Each synthesized profile uses its own seed, spectral mixture and event
parameters. Rain variants differ in density, surface resonance and low air;
wind variants differ in spectral weight and gust movement; water variants use
different flow, wave and bubble textures. Mechanical profiles include a quiet
tonal foundation. Vinyl has soft irregular surface ticks; tape has a finer
continuous air texture. Brown, pink and band-limited white noise are distinct
generated spectra, with no medical or therapeutic claim.

The generator produces 72 seconds, then makes a 69-second loop with a
three-second equal-power overlap. Different random events vary their timing,
duration, timbre and side. Each loop repeats after 69 seconds; this is not an
unlimited generative sound engine. Room processing and slow gain movement are
separate runtime features.

Continuous beds target −31 dBFS RMS before Vorbis encoding. Sparse water drops
use a peak bound instead of being pushed to the same average level. Encoding
can change the exact measured peaks, so the decoded files are checked as well.
The quieter level aims to sit beside the original recordings at ordinary
background fader positions without a large loudness jump.

## Reproduction

Run from a development checkout, with a Rust compiler and FFmpeg providing
`libvorbis`:

```sh
rustc --edition=2021 -O tools/generate-ambience.rs -o /tmp/skylofi-ambience
/tmp/skylofi-ambience assets
```

This explicit maintainer command generates only the 23 new known filenames.
It does not fetch files or modify the original nine recordings. PCM is created
by the Rust standard library and encoded by FFmpeg with bit-exact mode;
different compiler, libm or FFmpeg versions can produce different bytes.
The plugin never invokes this tool or compiles or downloads sounds at runtime.

The [decoded inventory](library-3.5-inventory.json) records duration, channels,
sample rate, peak/RMS levels, DC offset and file SHA-256. All 32 files have been
decoded completely for this inventory; all new files have finite samples,
no clipping, the expected duration and two channels. This technical check does
not replace the user's listening review for timbre, repetitive details or room
effect preferences.

The new synthesized sounds are [CC0](../SOUNDS-LICENSES.md). Original recordings
retain their existing CC BY, CC0 or public-domain provenance. The generator
source remains covered by the plugin's MIT code license.
