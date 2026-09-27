# Development audit — 2026-09-27

Scope: the ten commits from marketplace release `a98d927` (1.1.1) through
`b170102` on `dev`, plus the corrective changes accompanying this report.
Both remote branch tips were verified before editing. Work and tests use a
separate checkout; the installed plugin and marketplace branch are unchanged.

## What the development commits added

- `4b96fb6`: asynchronous fade-in/fade-out for playback and transport.
- `dbe27f4`, `3951d68`: native PanelHero, selectable station rows and equalizer.
- `23d77ae`, `738b3d5`: persistent appearance settings and a separate settings view.
- `ead9344`: adjustable VoxType retained volume and gradual ducking.
- `16f3cb2`: collapsible station, voice and nature sections.
- `e4579bc`: Now Playing metadata and finite-stream progress.
- `743ce5d`, `b170102`: process discovery without PID files and pidfd regression tests.

The architecture already has useful safeguards: argument-list subprocess calls,
no shell interpolation, mpv user configuration/scripts disabled, a serialized
controller, cancellable feed workers, plain-text metadata rendering, isolated
test audio, and pidfd-based termination without a numeric-PID fallback.

## Findings addressed

| Priority | Finding | Correction |
| --- | --- | --- |
| P1 | Absolute-volume fades excluded channels from ducking and Master changes, including mute; at completion a cached ducker value could leave an obsolete level. | Transport is a gain envelope composed with current channel, Master and ducking levels by one worker. |
| P1 | Fade-out released ownership before the once-per-second transport commit, allowing audio to return briefly before Pause/Stop. | The zero-gain envelope remains until resume or teardown. |
| P1 | Suffix-based process matching could terminate audio from a different runtime whose directory disappeared. | Match the exact runtime socket, retain pidfds and cleanup of this runtime's lost-PID processes. |
| P2 | Predictable JSON temporary files followed symlinks, and write failures were silently reported as successful commands. | Exclusive unique temporary files, atomic replacement, surfaced save failures. The symlink concern is local hardening, not a demonstrated remote exploit. |
| P2 | RSS XML had no size limit or explicit DTD prohibition; only enclosure strings were partially validated. | 8 MiB input limit, parser-level DTD rejection including UTF-16, HTTPS-only feed/redirect/enclosure validation, exclusive temporary playlist files. |
| P2 | Resume after disabling fades could preserve a stale silent envelope. | Resume explicitly restores transport gain even with animations disabled. |
| P3 | Reveal speed zero was coerced back to one. | Preserve zero; test the actual QML status mapping. |
| P3 | Hero animation timers could run while the panel or main screen was hidden. | Gate hero animation on panel visibility and the current screen. |

Also put `--` before mpv's media argument to prevent option interpretation,
make integration cleanup stop synchronously, and correct the documented ducking
default and cache lifetime.

## Verification and automation

Baseline: 48 Python tests and 5 Qt dropdown interaction tests passed. This did
not exercise the newly identified failure modes.

Final local result: **62 Python tests, 5 dropdown interaction tests and 3 panel
state tests passed**; manifest validation and whitespace checks passed. The
new Master=0-during-fade regression was also run against unmodified `b170102`:
it failed there and passed with the correction.

Added regression coverage for foreign deleted runtimes, fade completion and
silence retention, mute and dictation during fade-in, changed volume after
resume, safe writes and failed writes, bounded/DTD-free feeds, HTTPS validation,
and three native panel-state tests. Full local test command:

```sh
omarchy plugin validate .
dbus-run-session -- python -B -m unittest discover -s tests -p '*_test.py' -v
```

`tests/panel_test.py` requires an existing Wayland session and installed Omarchy
UI components. Its windows stay hidden and its D-Bus is private. The dropdown
test uses an offscreen Qt backend. These are state/interaction tests, not a
visual review of the complete panel on every monitor and theme.

Bandit 1.9.4 scans all eight Python modules/entry scripts. The medium/high gate
passes without skipped files or parser errors. Low-severity observations remain:
subprocess APIs with argument arrays (no shell), empty `feed_token` cancellation
markers misclassified as passwords, and best-effort cleanup that deliberately
preserves the original exception. They are reviewed observations, not a claim
of zero scanner warnings. The XML suppressions are limited to the parser whose
DTD rejection is covered by UTF-8 and UTF-16 regression tests.

The `Dev checks` GitHub Actions workflow targets only `dev`, uses read-only
permissions, pins checkout to a commit, runs backend/process integration tests,
and fails on medium/high Bandit findings or scanner errors. Native QML checks
remain local because the Ubuntu runner has no Omarchy desktop. No release,
marketplace update, tag, deployment, or merge-to-main step is included.

## Before version 2

- Finish the intended feature work. In particular, the Now Playing card only
  consumes `main_position/main_duration`; the catalog's podcasts use the
  background channel. Although the backend exposes their progress, the panel
  does not display it yet.
- Consider beginning fade-in when decoded audio becomes ready: a slow network
  connection can outlast the fade currently started after IPC becomes available.
- Visually exercise station navigation, nested pickers, collapse/reveal,
  scaling, themes and rapid settings changes on the supported desktop versions.
- Add recovery cases for structurally malformed settings and an empty/missing
  catalog. Existing code assumes their shapes; this audit does not certify those
  local-corruption cases as recovered.
- Check installed mpv/FFmpeg/Python/Qt updates and live station availability at
  release time. System packages and third-party stream operators are outside
  this repository's static-analysis gate.
- Update screenshots/changelog and assign the version only when release-ready.

Passing these checks is evidence for the tested scope, not certification that
all security vulnerabilities or all future marketplace checks are covered.

## Follow-on YouTube work

The later YouTube feature and its separate validation are described in
[the v2 development notes](docs/V2-ROADMAP.md). The original audit above remains
a record of the preceding ten-commit review.
