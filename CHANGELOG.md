# Unreleased

- Retry interrupted or stalled music with bounded backoff; pause, stop and station changes cancel pending recovery.
- Combine nature layers with a shared Nature volume and optional individual levels.
- Add offline tent rain, forest stream, morning birds and night crickets with source credits.
- Animate the enabled nature sounds only while the panel scene is visible and playing.
- Consolidate playback, recovery and ducking supervision; move podcast fetches outside the control lock.
- Migrate existing nature selections and levels automatically; coalesce queued slider changes.

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
