# v2 security and release review — 2026-09-27

Scope: runtime Python/QML, subprocess lifecycle, persistence and migration,
network inputs, installation contract, documentation and release workflow.
This is a code review with regression tests, not a guarantee of safety or a
marketplace certification. Community Omarchy plugins execute as the user.

## Boundaries reviewed

| Boundary | Protections and verification |
| --- | --- |
| Shell/process execution | Commands use argument arrays; mpv receives `--` before media. User mpv configuration and external scripts are disabled. No runtime installer or privileged helper. |
| YouTube links | HTTPS video URLs on explicit YouTube hosts only; canonical video IDs, no credentials, alternate ports, arbitrary extractors or playlist-only URLs. Saved data is revalidated, deduplicated and capped at 40 entries. |
| Extractor | yt-dlp ignores user configuration and plugins, disables remote component installation, browser cookies are not requested. Audio-only selection, bounded retries/timeouts. |
| Process cancellation | Linux pidfds pin identity before termination. Runtime socket markers distinguish this instance. Extractor descendants are pinned/frozen and checked against their parent before cancellation. Decoy processes survive tests. |
| RSS | HTTPS feeds, redirects and enclosures; 8 MiB maximum response, DTD rejection including UTF-16, 12-episode playlists, cancellable resolver outside the controller lock. |
| Files/state | Atomic writes through exclusive temporary files; errors surface to callers. Runtime directory must be owned and not a symlink, permissions 0700. JSON reads are bounded; malformed preferences and session state recover. Stop still works with an empty/damaged catalog. |
| IPC | Local Unix sockets in the private runtime; timeouts plus bounded response length/count. Non-object JSON and excessive event streams are rejected. |
| Audio safety | Fade gain composes with current channel/Master/ducking gain. Muting remains silent during and after fades. Pause/Stop retain zero gain until transport finishes. |
| UI content | External titles render as plain text; labels/URLs are bounded. Link removal needs confirmation. Motion settings and panel visibility gate decorative animation. |
| CI | Read-only repository permission, pinned checkout action, no persisted checkout credentials; backend/process tests and Bandit gate both dev and main. |

## Checks

- Omarchy's installed `omarchy plugin validate` checks the manifest, entry points,
  namespace and absence of symlinks.
- Real mpv regression suite uses silent local audio, isolated state/runtime and
  private D-Bus: transport, migration, recovery, fades, VoxType, MPRIS, process
  identity, extractor cancellation, URL rejection, settings corruption and IPC limits.
- Native QML compilation/state tests, pointer/keyboard dropdown/library tests,
  and a visible layout regression check cover the panel. Layout rendering uses
  the actual components with a window wrapper; the native popup is checked separately.
- Bandit 1.9.4: no medium/high findings and no scanner errors. Low-severity
  subprocess/XML heuristics are reviewed in context; the DTD rejection is tested.
- Official marketplace baseline V3 source reviewed at
  `omacom/omarchy-plugin-marketplace@fec33e6b14b3ab01e2c31faf36ea8e083965c82e`.
  Local working-tree analysis: `passed`, no findings or review capabilities.
  The marketplace must scan and approve the exact published commit separately.
- Each of the four Lofi Girl live presets decoded two seconds of real network
  audio through mpv with a null audio output. Automated tests use a deterministic
  local extractor and do not depend on YouTube availability.
- GIFs were rendered and visually inspected with sample entries. No personal
  library, cookies, account information or captured desktop is published.

## Test-related desktop crash investigation

Nine recorded crashes on this machine were `xdg-desktop-portal-hyprland`, not
Hyprland itself. They coincided with teardown of native UI tests' private
D-Bus sessions. The portal stacks ended in Wayland proxy calls during process
exit. Available memory ruled out exhaustion; the regular compositor and portal
processes remained running. Internal portal frames were not fully symbolized.

The test harness previously allowed automatic desktop-service activation.
Tests and demo rendering now use a bus configuration without service activation
directories. Follow-up UI tests produced no new portal dumps. This change does
not alter desktop settings or disable the user's normal portal service.

## Limits and operational notes

- YouTube and radio providers can change URLs, availability or extractor
  requirements; keep mpv, yt-dlp and its JavaScript runtime current. Private,
  restricted and account-dependent videos are not supported.
- Remote media is parsed by the installed mpv/FFmpeg/yt-dlp stack; this plugin
  cannot certify those dependencies or sandbox all their codecs.
- State and diagnostic logs stay local. Source URLs and extractor error details
  may occur in mpv logs; inspect/redact them before sharing a diagnostic bundle.
- Local code/catalog customization and the user's executable search path are
  trusted. This is not protection from an attacker already controlling that account.
- Store verification binds one exact commit. A GitHub release or a local passing
  scan alone does not confer the marketplace's Verified badge. See the official
  [security policy](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md)
  and [update workflow](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md).
