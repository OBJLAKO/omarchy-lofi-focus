# Independent review of the second UI revision

Review scope: every visible tab and primary block, playback states, source
selection, the saved-link form, mixer layers, settings, keyboard focus, scrolling,
long text, small windows, theme scaling and reduced motion. This review is
separate from implementation and uses the actual QML components with isolated
fixture state. It does not start audio, contact streams, or read the user's
saved library.

## Findings from the rejected revision

The rejected revision is preserved by commit `2d671ab`. Its original PNGs were
inspected before `docs/redesign/` was regenerated for the second revision.

| Priority | Finding | Acceptance condition for the second revision |
| --- | --- | --- |
| P1 | Header, transport, Master and navigation consume about 270 px before the Mix content; the second nature layer is already cut off. | Two enabled nature layers, their controls, and Add sound fit in the normal panel. More layers remain reachable by pointer and keyboard. |
| P1 | Previous/next glyphs do not explain whether they select a station or rewind playback. A finite mpv duration is insufficient to distinguish a radio stream from a seekable saved video. | Radio is explicitly live, never exposes a seek slider, and its navigation selects stations. A finite seekable YouTube source exposes clearly labelled seek controls. |
| P1 | Listen has two consecutive competing navigation rows, while changing to Settings shifts the entire navigation upward. | Source browsing, playback and mixing have distinct places. Navigation stays in one predictable location. |
| P2 | Master and Soundtrack are on separate screens without a clear explanation of their relationship. | Master is visibly the whole mix; channel levels sit with the channel they affect. |
| P2 | The first add-link form has no persistent field labels once a user has entered values. | URL and optional name remain identifiable with entered text and errors; form focus and cancellation are predictable. |
| P2 | Generic voice picker combines several source types in one long flat list. | Search and option descriptions make source choice understandable; open picker fits the available viewport and has reliable keyboard selection. |
| P2 | Settings hides the active playback context and uses potentially ambiguous “Keep audible” wording. | A user can identify the affected sound and understand that the dictation percentage is a relative ducking level. |

## Second revision evidence

The independent runner is `tools/ui_review_v2.py`. It takes one immutable source
snapshot, records source SHA-256 hashes, copies the actual QML components into a
temporary shell and sends actual Qt pointer, wheel and key events. Its fixture
host only records playback commands. The review uses a private D-Bus with no
service activation, an offscreen Qt window, and temporary HOME and XDG runtime,
configuration, cache and state directories.

Only `KeyboardPanel` window placement is replaced. The temporary surface retains
the real host border, padding and content insets: 460 × 600 px is the whole card,
not its usable content rectangle. This distinction exposed the initial V2 mixer
overflow that the earlier wide render fixture missed.

During the review, actual screenshots and interaction identified these issues:

| Priority | Evidence | Correction / verification |
| --- | --- | --- |
| P1 | Nature picker opened at x298 with 276 px content width in a 480 px window. | `TransformWatcher` invalidates the map-to-boundary origin when the trigger's ancestors move. Actual popup bounds and keyboard selection now pass in the normal fixture. |
| P1 | V2 initially still cut off the nature controls below the Voice group. | Compact channel rows now expose both Rain and Fireplace plus Add sound in the real 460 × 600 card. Geometry assertions accompany the screenshots. |
| P1 | A wheel gesture over an unfocused level track changed volume instead of scrolling the mixer. | Local slider lets an unfocused wheel reach the scrollable page. Independent wheel test checks content movement and the absence of any audio command. |
| P1 | Motion off still left the native switch knob at x23 instead of its new x3 target after 10 ms. | Local switch/action/slider controls now follow the plugin motion preference. The actual switch reaches its new position immediately with motion off; playback feedback stops on pause, close or reduced motion and settles after one short response. |
| P2 | Entered link values replaced the only visible field labels. | URL and optional name now have persistent visible labels; failed saves preserve entered values. |
| P2 | The shared map-to-item calculation was used without tracking ancestor transforms. | This was a layout lifecycle issue, not just a wrong constant; the corrected popup is checked after scrolling and at enlarged scale. |

The final run used the frozen QML after the per-bar font inheritance correction.
Every variant passed **15 actual interaction cases**, plus QtTest's initialization
case: **90 interaction cases + 6 initialization cases**, with zero failures.
There are **30 fresh screenshots per variant, 180 total**. Each `result.json`
records `{ "passed": 16, "failed": 0, "returncode": 0 }`; logs and screenshots
were regenerated from the same immutable snapshot.

| Variant | Offscreen window | Font base / scale | Result |
| --- | --- | --- | --- |
| Normal dark | 480 × 620 px; card 460 × 600 px | 12 px / 1.0 | 15 / 15 |
| Compact dark | 430 × 480 px; card 410 × 460 px | 12 px / 1.0 | 15 / 15 |
| Compact with enlarged text | 430 × 480 px; card 410 × 460 px | 18 px / 1.5 | 15 / 15 |
| Enlarged 125% | 595 × 770 px; card 575 × 750 px | 15 px / 1.25 | 15 / 15 |
| Enlarged 150% | 710 × 920 px; card 690 × 900 px | 18 px / 1.5 | 15 / 15 |
| Light palette | 480 × 620 px; card 460 × 600 px | 12 px / 1.0 | 15 / 15 |

The recorded [source hashes](redesign-v2-review/source-sha256.json) identify the
tested snapshot. `Panel.qml` SHA-256 is
`8130594ee68e98cc369b7fed07064b9c2eebe59e6e742e57e48f3086bdea3bd8`.

Representative renders:

- [Live radio](redesign-v2-review/normal/radio-live.png),
  [two-layer mix](redesign-v2-review/normal/mix-two-layers.png),
  [settings](redesign-v2-review/normal/settings-interface.png).
- [Finite recording](redesign-v2-review/normal/youtube-seek.png),
  [ended recording](redesign-v2-review/normal/state-ended.png),
  [saved live source without seek](redesign-v2-review/normal/saved-live-no-seek.png).
- [Labelled add form](redesign-v2-review/normal/library-add.png),
  [failed save](redesign-v2-review/normal/library-save-failed.png),
  [filtered collection](redesign-v2-review/normal/library-filter.png),
  [delete confirmation](redesign-v2-review/normal/library-remove.png).
- [Voice picker](redesign-v2-review/normal/voice-picker.png),
  [bounded nature picker](redesign-v2-review/light/nature-picker.png),
  [voice failure](redesign-v2-review/normal/voice-failed.png).
- [All layers scrolled into view](redesign-v2-review/normal/mix-all-layers-bottom.png),
  [compact enlarged layout](redesign-v2-review/compact150/settings-interface.png).

## Interaction coverage

Real pointer clicks verified Play/Pause, Stop all, source selection, adding a
saved link, save-error feedback with retained fields, removal confirmation,
background selection and Retry. Real keys verified recording seek, source and
collection search, native Tab traversal, Escape hierarchy and volume arrows/Home.
Thirty consecutive Tab presses traversed the active mixer; every focused mixer
control remained within its viewport. A real wheel gesture moved the overflowing
mixer without emitting any volume command.

Geometry checks verified stable navigation and dock across all three tabs, both
default nature sliders fitting the normal panel, dock bottom inside the card,
and dropdown content inside window bounds after filter/layout changes. The
125% run initially flagged a 1 px overlap of an item's empty bottom padding;
its actual slider and focus outline were fully visible. The final criterion
checks the interactive bounds rather than requiring invisible padding to fit.

Radio fixtures deliberately include a bogus positive duration while
`can_seek=false`: no timeline or previous/next transport exists. Saved finite
recordings supply `source_kind=recording` and `can_seek=true`; unknown/live saved
sources remain non-seekable. Only the ended recording fixture shows Replay.
Long mixed-script titles elide safely. The two enabled nature layers expand to
every catalogued layer for scrolling and keyboard checks.

Switch position was sampled after a 10 ms event-loop interval with motion off.
Playback feedback was checked while starting, after its 340 ms response settled,
and immediately on pause, reduced motion or panel close. Per-bar `sans-serif`
overrides reached dock, library and nature actions in all six runs.

Reproduction: `python tools/ui_review_v2.py --variant all`. The command starts
only the isolated Qt fixture; audio and stream access are absent.

## Scope and remaining observations

The offscreen replacement does not test the compositor's layer-shell placement,
outside-window dismissal or the shared Omarchy `KeyboardPanel`/`WidgetButton`
window transitions. Those host transitions retain the shell's policy. The
plugin's own controls and feedback obey its motion preference. Native transport,
audio performance and marketplace suitability have separate validation.

The compact 430 × 480 px, 150% fixture intentionally has a short content viewport.
It requires scrolling to work with the form or settings; playback and overall
volume stay fixed and accessible. This is a usable fallback, not a claim that
every settings group or the entire mixer fits simultaneously at that size.

Remove actions retain compact desktop targets of about 28 px, slightly below the
32 px composition token. Actual pointer and keyboard removal work; this is a
minor comfort detail for future touch-oriented use, not a desktop blocker.

## Current verdict

**The second revision is ready for user preview on the experimental branch.**
The reviewed implementation resolves the first revision's main hierarchy,
navigation, density and radio-transport problems. Source selection leads the
Listen page, mixing is understandable, and the stable dock keeps playback close
while editing settings. The independent interaction/geometry checks found no
remaining implementation blocker in the six tested variants. The review does
not substitute for the user's judgment of visual taste or marketplace review.
