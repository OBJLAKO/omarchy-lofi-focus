# 1.3.0 — local acceptance build

- Fix Master and VoxType failing when an older process owns the MPRIS name:
  a separately supervised volume worker and immediate master updates no longer
  depend on the media bridge. Verify mpv command acknowledgments.
- Add an independent Nature channel with five bundled, attributed audio loops.
- Add four chill stations and a centered vector coffee icon.
- Regression tests cover a conflicting MPRIS owner, dead volume worker,
  three-channel scaling, pause, resume, and preserved ambience selection.

# 1.2.0 — local acceptance build

- Add ongoing Linux and developer podcasts from official publisher feeds.
- Add Master volume while preserving the Music/Voice balance.
- Automatically reduce both channels to 20% during VoxType recording, with
  an immediately accessible opt-out in the panel. No hotkey/config edits.
- Test recording/transcribing transitions, absent state, new volume during
  recording, station changes, opt-out and master mute/restore with real mpv.

# 1.1.0 — local acceptance build

- Keep mutable settings outside the plugin watcher; serialize concurrent changes.
- Separate music and voice roles; remove station mixing controls.
- Use native searchable selectors, independent volume sliders and a coffee icon.
- Keep voice playback uninterrupted when switching music.
- Queue quick UI actions and preserve the final scroll volume update.
- Fix stopped-state playback and MPRIS PropertiesChanged callbacks.
- Add The Changelog publisher RSS playlist with no new packages.
- Preserve upstream MIT attribution and standard Git-based plugin packaging.

Verified: Omarchy manifest validation; QML parsing; isolated integration tests
with real mpv IPC; live panel screenshot; music playback; publisher RSS and
podcast audio decoding through mpv's null output. Runtime changes observed
without plugin reload messages. Remote streams remain subject to availability.

Public release, repository URL and marketplace submission await user acceptance.
