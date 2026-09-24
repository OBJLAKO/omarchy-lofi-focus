# Bundled ambience recordings

These audio files have their own licenses, separate from the MIT plugin code.
The five original recordings were copied unchanged from [Blanket](https://github.com/rafaelmardojai/blanket/tree/master/data/resources/sounds).
Loop preparation by Porrumentzio for rain, storm, waves and wind; no further
sound edits were made to those five files for Lofi Focus.

| File | Original creator and source | License |
| --- | --- | --- |
| assets/rain.ogg | alex36917 — [rain ambience](https://freesound.org/people/alex36917/sounds/524605/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| assets/storm.ogg | digifishmusic — [Infinite Storm.wav](https://freesound.org/people/digifishmusic/sounds/41739/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| assets/waves.ogg | Luftrum — [oceanwavescrushing.wav](https://freesound.org/people/Luftrum/sounds/48412/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| assets/wind.ogg | felix.blume — [Wind](https://freesound.org/people/felix.blume/sounds/217506/) | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| assets/fireplace.ogg | ezwa — [Fireplace](https://soundbible.com/1543-Fireplace.html) | Public domain |

See also Blanket's [sounds licensing](https://github.com/rafaelmardojai/blanket/blob/master/SOUNDS_LICENSING.md).

## Additional nature layers

These recordings are bundled locally; playback never downloads them or contacts
an external sound service. All four are real field recordings. The tent-rain
source was obtained from Freesound's [public high-quality MP3 preview](https://cdn.freesound.org/previews/484/484723_9159316-hq.mp3); the other
three were obtained from [Blanket at commit
`9d229d2be7cb6619135d55ff9e49926e40298686`](https://github.com/rafaelmardojai/blanket/tree/9d229d2be7cb6619135d55ff9e49926e40298686/data/resources/sounds).

| File | Original creator and source | License | Preparation for Lofi Focus |
| --- | --- | --- | --- |
| assets/tent-rain.ogg | Breviceps — [Rain on tent](https://freesound.org/people/Breviceps/sounds/484723/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Two-second loop crossfade; converted from the HQ MP3 preview to Ogg Vorbis |
| assets/stream.ogg | gluckose — [stream2.wav](https://freesound.org/people/gluckose/sounds/333987/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Two-second loop crossfade; gain +8 dB; re-encoded as Ogg Vorbis |
| assets/birds.ogg | kvgarlic — [WoodThrushinMorningShawneeForestMay272012.wav](https://freesound.org/people/kvgarlic/sounds/156826/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Upstream loop preparation by Porrumentzio; additional two-second loop crossfade; gain +3 dB; re-encoded as Ogg Vorbis |
| assets/night.ogg | Lisa Redfern — [Crickets Chirping At Night](https://soundbible.com/2083-Crickets-Chirping-At-Night.html) | Public domain | Two-second loop crossfade; re-encoded as Ogg Vorbis |

The original sources and licenses were checked on 2026-09-24. Audio licenses are
independent of the MIT license covering this plugin's code.

### Preparation details

The four new loops use 44.1 kHz stereo Vorbis (`libvorbis`, quality 4). Their first
two seconds are blended into the final two seconds with an equal-power crossfade,
then the loop begins at the original two-second mark. This avoids a silent
fade-out/fade-in at every repeat. The files contain no added speech or music.

The FFmpeg filter used below takes `GAIN` in dB (0, 8, 3 and 0 for tent rain,
stream, birds and crickets respectively). FFmpeg is only a maintainer tool;
users do not need it to install or play the sounds.

```text
[0:a]volume=GAINdB,asplit=2[a][b];
[a]atrim=start=2,asetpts=PTS-STARTPTS[tail];
[b]atrim=end=2,asetpts=PTS-STARTPTS[head];
[tail][head]acrossfade=d=2:c1=qsin:c2=qsin[out]
```
