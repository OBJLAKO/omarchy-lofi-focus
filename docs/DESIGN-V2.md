# Skylofi design v2

This revision makes Skylofi a quiet listening utility: choose a source, balance
the surroundings, return to work. The first redesign put a large playback card,
master slider, navigation, source navigation and search above the station list.
Each block looked equally important. Opening Settings moved the tabs upwards;
small text and repeated status information made the panel feel like a control
dashboard. The replacement gives source browsing the main space and keeps
playback controls in one stable dock.

## Reference research

The following official sources were checked on 2 October 2026. These are design
references, not a proposed GTK migration or a claim that the QML panel is GNOME.

| Reference | Useful observation | Skylofi decision |
| --- | --- | --- |
| [Shortwave](https://apps.gnome.org/Shortwave/) and its [compact interface](https://static.gnome.org/catalog/app-screenshot/de.haeckerfelix.Shortwave/image-3_orig.png) | The product is explicitly a radio library with station discovery and a layout for small and large screens. | Source selection is the primary Listen task; controls describe radio playback rather than pretending every stream is a recording. |
| [Amberol](https://apps.gnome.org/Amberol/) and its [interface](https://static.gnome.org/catalog/app-screenshot/io.bassi.Amberol/image-1_orig.png) | The official product positions playback as its focused purpose and offers an adaptive interface. | One obvious playback action; avoid decorative feature panels and unnecessary transport buttons. |
| [GNOME navigation guidelines](https://developer.gnome.org/hig/guidelines/navigation.html) | A small set of peer views suits a flat view switcher; each view needs a clear subject. | Listen, Mix and Settings remain peer pages with no additional nested navigation hierarchy. |
| [GNOME boxed lists](https://developer.gnome.org/hig/patterns/containers/boxed-lists.html) | Short static lists are grouped semantically; rows distinguish primary and secondary copy, with symbolic icons and trailing remove actions. | Settings use two quiet groups; active atmosphere layers use aligned rows with a remove action at the end. |
| [GNOME typography](https://developer.gnome.org/hig/guidelines/typography.html) | System fonts, a small set of relative sizes and restrained weights support readable interfaces. | Retain the Omarchy font family and scale; increase useful small text instead of adding custom fonts or oversized display type. |
| [GNOME UI styling](https://developer.gnome.org/hig/guidelines/ui-styling.html) and [accessibility](https://developer.gnome.org/hig/guidelines/accessibility.html) | Theme variables, descriptive accessible names and tests with larger text and keyboard navigation reduce custom-control failures. | Use the existing Omarchy palette, visible focus, state text and explicit labels; verify compact and enlarged layouts. |
| [Apple Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion) | Motion should communicate state, remain brief and optional, and allow people to continue acting. | Playback commands and focus never wait for animation; local feedback settles quickly and has an off mode. |
| [Samsung One UI 7 design](https://design.samsung.com/global/contents/one-ui-7/) and [basic layout](https://developer.samsung.com/one-ui/layout/basic.html) | The official design account emphasizes coherent information hierarchy and interactions that make changes understandable. | Keep shared frame geometry, row alignments and control behavior consistent. This borrows a quality principle, not mobile screen shapes. |

The composition below is an implementation proposal inferred from those
principles. Dimensions, dock position and control choices are Skylofi-specific.

## Visual system

`SkylofiStyle.qml` is the local composition contract. It reads the host palette,
font family, font scale, spacing scale and corner radius. Theme changes therefore
remain authoritative. No image background, new font dependency, arbitrary neon
color, wallpaper blur, shadow stack or decoration is needed.

| Token | At the default host scale | Use |
| --- | ---: | --- |
| Card width / height | 460 / 600 px | KeyboardPanel geometry including its padding and border; usable inner width is approximately 416 px |
| Outer padding | 20 px | Applied once by the host panel |
| Group / control / small gap | 16 / 8 / 4 px | Layout rhythm |
| Station row | 56 px minimum | Title and one secondary line, with a generous full-row target |
| Control height | 36 px | Search, selectors and primary actions |
| Small action target | 32 px minimum | Close, remove and secondary controls |
| Body / label / caption / title | 13 / 12 / 11 / 18 px | Four relative type sizes, theme font family |
| Ordinary playback dock | About 104 px | Source, state, playback and overall volume |
| Group surface / divider | 3.5% / 12% foreground | Subtle hierarchy without framing every control |
| Selected / hover fill | 11% accent / 7.5% foreground | Distinct chosen state and temporary pointer feedback |

Primary text uses the theme foreground. Secondary text uses 76% alpha; purely
auxiliary marks can use 60%. Do not lower text opacity to signal important
disabled-state explanations. Accent is reserved for the active view, selected
source, focus and the main action. Error color accompanies words, never replaces
them. Header title is semibold; most row titles are regular. Selected source has
a check or small playback mark in addition to color. In rounded themes reuse the
host radius; a square Omarchy theme stays square.

## Stable frame

Order from top to bottom:

1. One 32 px header: **Skylofi** on the left, close target on the right.
2. One 36 px view switcher: **Listen · Mix · Settings**. Labels sit on a common
   baseline; selected state uses a short accent underline or a restrained fill.
3. The active scrollable page, separated by 12–16 px of breathing room.
4. A divider and persistent playback dock.

Do not show a slogan, duplicate page name, full-width equalizer or additional
hero title. Switching pages keeps header, tabs and dock at identical positions.
The page body alone scrolls. Each page remembers its own scroll position. At
short screen heights the body shrinks and remains scrollable; playback, volume
and navigation stay reachable. The dock can reserve additional height for a
verified finite recording timeline or an error message without relocating the
header. An ordinary radio state must not consume that empty extra height.

## Listen

The page begins with an understated **Radio / Saved** source filter on the left.
The saved-library count is small supporting information. It is not another set
of three large primary navigation tiles. Radio has a search field followed by
one quiet station list; names have room, descriptions fit a single secondary
line, selected state is visible, and clicking anywhere on a row starts it.
Station icons remain small symbolic marks rather than dark decorative squares.
The selected station is not repeated in several headings.

The saved view has search plus one **Add link** action. The form appears inline
with a URL field, optional name and clear Save/Cancel actions. Labels persist
while typing. Validation appears at the field, preserving the typed value.
Empty library copy gives one instruction and the add action. Removing a saved
entry expands a compact confirmation for that entry; Escape cancels before
closing the panel. Long titles elide, with an accessible full name and tooltip
where useful. Delete controls must not overlap titles or activate playback.

Dock source information is a maximum of two lines: source title and a short
state such as **Live radio**, **Paused**, **Connecting…** or **Recording**. It
contains one obvious **Play / Pause / Resume / Replay** action and a secondary
**Stop all** action. A separate row says **Volume**, shows the overall slider and
a percentage. No ambiguous second slider called Master appears elsewhere.

### Radio and recording are different products

Radio, including the built-in YouTube live stations, has **no timeline, rewind,
fast-forward, previous-track or next-track buttons**. Choosing another station
happens through the station browser. A positive duration reported by mpv is not
proof that radio became a seekable recording: live DASH manifests can expose a
window duration.

Saved YouTube entries may show a recording timeline only when the source is
explicitly known to be finite and seekable, the backend supplies a valid duration,
and playback has a valid position. Unknown/live sources remain radio-like. A
timeline with elapsed/total labels is sufficient; do not add redundant ±15-second
buttons. Ended finite media show Replay. Source-kind information must come from
the backend or the selected library item, not duration heuristics alone.

## Mix

The page contains three functional blocks; avoid a repeated Your mix title and
introductory paragraph.

**Soundtrack** has one labeled level row. It controls the main source relative
to other layers; the dock Volume remains the overall output. Values stay aligned
on the right and never jump horizontally when reaching 100%.

**Voice** has one source selector, initially Off. Enabling a source reveals its
level below, with a short explanation only when relevant. Loading/error state
appears beside this group with Retry if appropriate. When YouTube prevents voice
mixing, use a readable explanation and disabled source controls; do not silently
hide the remembered choice or conflate the voice failure with station playback.

**Atmosphere** has a small active-layer count and one Add sound action. With no
layers the empty state names a few available examples and points to that action.
Each active layer row contains a small symbolic icon/name, slider, percentage and
trailing remove target. Only enabled layers occupy space. All ten layers work
without overlaps; this list scrolls while the dock remains fixed. Adding/removing
a row does not change panel dimensions or make the Add sound action inaccessible.
The dropdown is anchored to its control and supports search, Escape and arrows.

## Settings

Two semantic groups keep the page calm:

**Playback** contains Fade in and out, its duration when enabled, Lower sound
while dictating and its remaining-level control when enabled. Captions explain
effect in one short sentence. Dictation support names VoxType in supporting copy,
so the integration is understandable rather than suggesting all microphones are
observed. Prefer **While dictating** or **Remaining volume** to Keep audible.

**Interface** contains Interface motion and Playback feedback. Motion off means
no local view/disclosure/hover transitions or animated indicator.
The indicator preference can remain stored while its control is disabled; show
one short hint if its dependency is otherwise unclear. Remove switches for
unused steam, glow, reveal speed and collapsible sections from visible UI.
Keyboard shortcuts belong in a concise optional help footer or tooltip; they
must not dominate the settings page.

Setting rows have one label with an optional wrapped caption and one trailing
switch. The text column flexes; trailing controls keep a fixed column. Clicking
the row can toggle its switch if this does not conflict with another interactive
control. Contextual sliders sit below their parent switch within the same group,
with consistent labels and aligned readouts.

## State and motion contract

| Trigger/state | Behavior | Motion |
| --- | --- | --- |
| Hover or press | Temporary subtle fill, immediate action dispatch | 100 ms color/opacity only |
| Active tab changes | One page becomes interactive immediately; focus stays on navigation | 160 ms opacity, optional 4 px shift; no panel/header movement |
| Voice level or duration becomes relevant | Parent and dependent control remain visibly associated | 180 ms disclosure within scrollable body |
| Layer added/removed | Fixed dock/frame; neighboring rows settle with the list | At most 180 ms, no spring or bounce |
| Connecting | State text; optionally a small indeterminate mark | Stops when settled, closed or reduced motion |
| Playback starts | Small mark in the dock responds once and settles | Optional 340 ms one-shot; no perpetual equalizer |
| Playing steadily | Static selected mark and clear status text | None; no ongoing animation workload |
| Paused, stopped, failed or panel closed | Stable state; errors include Retry where applicable | All repeating animation stops |
| Motion disabled | Identical controls and information | Immediate property changes, static status mark |

Animations must not delay IPC commands, keyboard focus, closing or hit testing.
Invisible pages are not interactive and do not run repeating animation. Avoid
animated geometry for the frame; animate local disclosure and restrained state
feedback only. Motion settings apply to dropdowns and custom controls too.

The implemented local controls are `SkylofiButton`, `SkylofiSwitch` and
`SkylofiSlider`. Their feedback uses 100 ms color changes, 120 ms level updates,
140 ms switch/chevron movement, 160 ms page opacity and 180 ms contextual
disclosure. All use short easing without bounce. The playback indicator has a
single 120 ms rise and 220 ms settle, with no infinite loop. Closed/invisible
controls finish feedback and repeating animation does not run. Local switches
also keep disabled explanations readable and support clicking their labels.

Omarchy's host `KeyboardPanel` and bar widget retain the shell's own mapping and
theme transitions. Interface motion governs Skylofi's internal controls and
pages; it does not rewrite the shared desktop shell or its window animation.

## Acceptance review

Review real QML renders and interaction, not only a design description. Check:

- Radio playing, radio paused, connecting/reconnecting, failure and idle: no seek
  or timeline appears even if a bogus positive duration is injected.
- Verified finite recording, unknown live saved source and ended recording:
  timeline behavior and primary action match source capabilities.
- Listen with long station/title text, zero saved links, many links, search with
  no matches, add validation, delete confirmation and unavailable yt-dlp.
- Mix with voice Off/loading/error/playing, blocked voice, zero/two/ten atmosphere
  layers, dropdown open, remove target and 0%/100% aligned readouts.
- Settings with every combination of fade/dictation/motion toggles, long captions
  and keyboard use. Disabled dependencies are understandable.
- Default 430 px test fixture, real panel card width of at most 460 pixels with
  its actual padding/border, 480 px available content height and 1.5× text/spacing
  scale. No content clips
  behind the dock; every control can be
  scrolled into view. The scrollbar does not cover readouts/remove controls.
- Dark and light palette; visible focus for every custom control, descriptive
  accessible names, keyboard search/navigation and Escape hierarchy.
- Each tab keeps the same header/navigation/dock geometry; playback and overall
  volume remain available while working in Settings.

The final verdict belongs to the independent user-role reviewer and integration
review, after inspecting the implemented screens. A written specification alone
is not evidence that the interface is comfortable or visually correct.
