# Lofi Focus ☕

One chill station. An optional background voice. One click to return to work.
A native Omarchy shell widget, using the current theme, fonts and panel controls.

- **Left click:** start your last station and voice; pause/resume both.
- **Right click:** choose music, choose a voice, adjust Master volume or their individual balance.
- **Middle click:** next music station. **Scroll:** music volume.
- Switching music leaves the voice playing. Music cannot be selected as a voice.

Includes SomaFM chill/ambient stations, talk radio, ATC and **The Changelog**
software development interviews, Changelog & Friends, LINUX Unplugged,
Talk Python To Me and Linux Matters. Only ongoing shows are included. Podcast audio comes from the publisher's RSS
feed; up to 12 recent episodes play consecutively. The feed is cached for six
hours. A new voice session starts at the latest episode; playback position is
not saved. Live streams depend on broadcaster availability and region.

## Install

Use Omarchy's normal **Plugin → Add** flow with this repository's Git URL,
or `omarchy plugin add <repository-url> --enable`.
No install script, pip environment, YouTube downloader or extra package step.
Uses Omarchy's bundled mpv, Python, python-gobject, jq and util-linux.
Requires the Quickshell-based Omarchy shell with third-party plugin support.

The repository root is the installable plugin (`manifest.json`, id `sky.lofi`).
Update with `omarchy plugin update sky.lofi`.

## Storage

Settings are saved in `$XDG_STATE_HOME/sky.lofi/settings.json`
(default `~/.local/state/sky.lofi/settings.json`). An existing in-plugin
`settings.json` is read once for migration. Runtime sockets, status, podcast
playlists and logs use `$XDG_RUNTIME_DIR/sky.lofi/`.
**Playback never writes to the watched plugin directory**, so changing volume
or station does not trigger a shell reload.

Music belongs to the `lofi` category in `stations.json`; other categories are
voices. Podcast entries use `kind: "podcast"` and an HTTPS RSS URL. No audio is
bundled or rehosted. Sources: [SomaFM](https://somafm.com/listen/),
[The Changelog](https://changelog.com/podcast), and the broadcasters named in
the station catalog. Catalog edits are code changes and reload the plugin.

## Development

```sh
omarchy plugin validate .
dbus-run-session -- python tests/player_test.py
```

The tests use real mpv with silent local audio, isolated settings/runtime and
D-Bus. They cover start/pause/resume, separate roles, volume, concurrent writes,
remembered choices and unchanged plugin source files.

CLI: `./lofi-player play|pause|resume|toggle|stop|next|prev|status`,
`./lofi-player start <music-id>`, `./lofi-player bg <voice-id|off>`,
`./lofi-player vol main|bg <0-100>`. Media keys control both channels through MPRIS.

Derived from [omarchy-lofiatc](https://github.com/dmltallen/omarchy-lofiatc)
by dmltallen and the local sky.lofi extension. MIT license; upstream attribution
is preserved in LICENSE.

Release/public marketplace submission is pending local user acceptance.

## VoxType and master volume

**Master** scales Music and Voice together without changing their balance.
The **Quiet while dictating · VoxType** switch is enabled by default: while
VoxType records, both streams play at 20% of their chosen effective volume.
Normal volume returns when recording ends (including during transcription).
Changing volume or station during dictation respects the same scaling.

No F9 binding edits, hooks, extra packages or system audio changes are needed.
The existing MPRIS helper reads VoxType's state every 100 ms. With no running
VoxType, or a missing/disabled state file, volume is unaffected. Standard
`state_file = "auto"` and custom state paths in VoxType's default config are
supported. A daemon launched with a separate config is not auto-discovered.

CLI: `./lofi-player vol master 50`, `./lofi-player ducking on|off`.
