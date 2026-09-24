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
