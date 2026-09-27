# Lofi Focus v2 — listening first

## Implemented on dev

A saved YouTube shelf shares the same foreground player, Master volume,
VoxType ducking and nature mixer as radio. A single Now Playing card owns
metadata, progress and transport. The source tabs change browsing, not playback.
The add-link form opens on demand so saved entries and nature controls stay
close together. Visuals use Omarchy's existing palette, fonts and control kit.

The screenshots are renders of the actual QML with sample state and the local
theme. Their window wrapper is offscreen; native panel state and library pointer/
keyboard interactions have separate tests.

## Suggested next steps, in priority order

1. **Saved mixes.** One click for a named combination such as Conversation +
   Rain, Deep Work or Evening Jazz. Store source, nature choices and levels;
   avoid starting audio merely by editing a mix.
2. **Sleep/focus timer.** 15/30/60 minutes or a custom duration, a subtle
   countdown and a soft stop. Keep cancellation next to the timer.
3. **A short listening queue.** Add a few saved videos, drag to reorder and
   continue to the next episode. Make end-of-queue behaviour explicit.
4. **Library search and favourites.** Useful after the shelf grows; do not add
   another always-visible toolbar while most people have only a few entries.

For the first public v2 release, prioritise a reliable listening loop and a
short demo showing “paste → play → add rain → resume tomorrow”. Good defaults,
clear failure states and a focused README are more useful than a large feature
list. GitHub stars remain a result of people finding the plugin useful.

## Release checks still open

- Finish the intended feature scope before assigning a version or tagging.
- Visually check supported themes, scale factors and small laptop displays.
- Extend local-corruption recovery for malformed settings and empty catalogs.
- Complete background-podcast progress presentation separately from the new
  foreground YouTube card.
- Verify supported system-package versions and current stream availability.

## YouTube validation performed

- Canonical HTTPS YouTube-only links; tracking parameters and playlist context
  discarded; persisted entries revalidated; library size and titles bounded.
- Actual mpv tested with an offline extractor and range-capable HTTP fixture:
  save/reopen/deduplication, source switching, seek/resume, EOF/replay, removal,
  cancellation of slow extraction plus a nested helper, unrelated-process safety.
- YouTube fade-in waits for decoded audio instead of expiring during extraction.
- Real public YouTube audio played through installed mpv 0.41.0 / yt-dlp
  2026.08.19 with the null audio output and a two-second playback limit.
- Medium/high Bandit gate, manifest validation and existing radio/mixer tests.

No main-branch merge, release tag or marketplace publication is part of this work.
