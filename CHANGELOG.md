# 3.0.0-alpha.2 · design revision

- Keep navigation and compact playback/overall-volume controls stable across tabs.
- Rework every Listen, Mix and Settings block, source rows, library forms and levels.
- Fit searchable dropdowns inside the panel and preserve reliable keyboard focus.
- Let unfocused slider wheel events scroll the page without changing volume.
- Make local controls honor the interface-motion preference, including switches.
- Confirm live/finite source capabilities in a bounded Rust extraction proxy;
  remove radio timelines/rewind and disable seeking through CLI and MPRIS.
- Reconnect radio/live EOF instead of presenting it as a finished recording.
- Record an independent rendered UI audit and an evaluation of audio-engine options.

# 3.0.0-alpha.1 · rustTest experiment

- Redesign listening around Listen, Mix and Settings, with clear layer controls,
  searchable sources and keyboard access.
- Replace decorative motion with focused transitions and an independent motion setting.
- Move playback supervision and media integration into a persistent Rust controller.
- Keep native QML, mpv audio and the existing `sky.lofi` preferences and library format.
- Add controlled performance comparisons, actual native integration tests and an
  explicit build/bundle workflow. Marketplace publication remains separate.

# 2.0.0 — 2026-09-27

- Four official Lofi Girl live presets: Study beats, Synthwave, Jazz lofi and Sleep & chill.
- Animated playback indicator, smooth section folding and keyboard-accessible section headers.
- Recover malformed settings/session files, bound JSON reads and keep Stop usable with an empty catalog.
- Isolate test D-Bus services to prevent auto-starting desktop portals during UI tests.
- New v2 project cover and lightweight GIF walkthroughs.
- Saved YouTube listening shelf: validated links, optional titles, audio-only
  streaming through yt-dlp, position memory, seeking and replay.
- Stop cancels mpv's extractor and helper processes using verified pidfds.
- Unified Radio/YouTube tabs, shared audio controls, collapsible add-link form,
  clearer metadata, higher-contrast helper text and removal confirmation.

- New station list, animated hero, appearance settings, collapsible sections,
  and Now Playing metadata/progress.
- Configurable VoxType ducking and playback fades.
- Compose fades with live mix levels; preserve silence through Pause/Stop.
- Restrict orphan cleanup to the owning runtime while retaining pidfd safety.
- Harden atomic state writes and bound/validate podcast feeds.
- Add regression tests and a CI/security gate for dev and main. See DEV-AUDIT.md.

# 1.1.1

- Pin each process with a Linux pidfd before checking its identity; use that same handle for SIGTERM, exit polling and SIGKILL, with no numeric-PID or process-group fallback.
- Fetch podcasts directly inside the bounded resolver process so cancellation cannot leave a separate fetch child or require killpg.
- Replace outdated playback workers automatically after an update, preserving running audio and saved levels.
- Add regressions for PID-file replacement, exited and unrelated processes, forced termination, feed cancellation and controller upgrades.

# 1.1.0

- Close an open dropdown when its trigger is clicked again; preserve outside-click and keyboard dismissal.
- Keep VoxType automatic Pause/Play from overriding enabled dictation ducking, and log transport command sources.
- Add Kalizo Lo-fi, Purrple Cat and Lofi Cafe Chilling, whose operators state that their streams are ad-free.
- Remove SomaFM following its updated third-party app policy; migrate saved stations without mislabeling active audio.
- Retry interrupted or stalled music with bounded backoff; pause, stop and station changes cancel pending recovery.
- Combine nature layers with directly adjustable individual levels, shown beside each selected sound.
- Add offline tent rain, forest stream, morning birds and night crickets with source credits.
- Use a compact panel with an Add sound picker and collapsed settings; remove nature animations and the separate scene.
- Consolidate playback, recovery and ducking supervision; move podcast fetches outside the control lock.
- Migrate existing nature selections and effective levels automatically; remove the hidden group gain and coalesce queued slider changes.

# 1.0.3

- Keep playback state, pause/resume and volume control working when the music stream exits but voice or nature audio remains.
- Show a disconnected music stream with an explicit reconnect action.
- Preserve mpv diagnostic logs for the current and previous stream attempt.

# 1.0.2

- Animate gentle steam above the cup while the settings panel is open.
- Keep the bar and panel synchronized from player status responses, including after missed file notifications.
- Let the player decide toggle state instead of trusting stale UI state.

# 1.0.1

- Scroll the bar widget to adjust Master volume, preserving all channel balances.
- Remove I Love Chillhop and FluxFM Chillhop after reported advertising interruptions.
- Add Lilo-Fi Radio using its official player stream; the operator states no ads
  or mid-stream interruptions. Make it the default for new installations.

# 1.0.0

First public release.

- Native, theme-aware Omarchy panel with a centered coffee icon.
- One music station, optional background voice and independent nature channel.
- Eleven chill/ambient stations and ongoing developer/Linux podcasts.
- Five bundled nature loops with complete audio attribution.
- Master volume plus individual channel levels and automatic VoxType ducking.
- Remembered settings stored outside the plugin watcher to avoid shell reloads.
- Independent volume supervision and MPRIS media-key support.
- Standard Git-based Omarchy installation with no extra setup steps.
- Integration coverage for playback, volume, dictation and process recovery.
