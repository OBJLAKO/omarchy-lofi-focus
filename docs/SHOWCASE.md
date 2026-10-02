# Skylofi showcase and repository metadata

Research date: 2026-10-02. This note records presentation choices and supported
GitHub settings; it does not claim a search ranking or marketplace approval.

## Repository identity

Configured repository description:

> Skylofi: lo-fi radio, YouTube audio and nature-sound mixes for Omarchy. Rust controller, QML interface, mpv playback.

Configured homepage:

`https://omarchyplugins.com/plugin.html?id=sky.lofi`

Configured topics:

`omarchy`, `omarchy-plugin`, `rust`, `qml`, `quickshell`, `lofi`,
`internet-radio`, `ambient-sounds`, `youtube`, `voxtype`.

These identify the platform, implementation and use case. GitHub topics appear
on the repository and support topic browsing/search. Names use lowercase
letters, numbers and hyphens, with at most 50 characters each and 20 topics per
repository. Ten specific topics are sufficient here.
[GitHub topic documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics).

Default GitHub repository searches match the name, description and topics.
README contents can be searched with `in:readme`. Keeping the platform and
purpose in the opening text also gives readers and tools clear project context;
GitHub documents no guarantee that this improves external or AI search rankings.
[GitHub repository search](https://docs.github.com/en/search-github/searching-on-github/searching-for-repositories).

Description/homepage can be changed in the About editor or through the documented
`PATCH /repos/{owner}/{repo}` endpoint. Topic replacement has its own
`PUT /repos/{owner}/{repo}/topics` endpoint; it replaces the complete topic set.
These are repository settings, not changes produced by committing the README.
[GitHub repository REST endpoints](https://docs.github.com/en/rest/repos/repos#update-a-repository).

These settings were applied through GitHub's supported repository editor API
and read back on 2026-10-02. Do not rename the existing
repository or alter language statistics to imply that the QML interface, mpv
decoder or retained Python reference has become Rust code.

## Marketplace destination

The live [marketplace catalog](https://omarchyplugins.com/catalog.json) was checked
for repository `OBJLAKO/omarchy-lofi-focus`. Its plugin ID is `sky.lofi` and the
detail link is [the Skylofi listing](https://omarchyplugins.com/plugin.html?id=sky.lofi).
At research time it records version 2.0.0 under the name **Lofi Focus**.
The native Skylofi 3 update is [request #9719](https://github.com/omacom/omarchy-plugin-marketplace/issues/9719),
awaiting maintainer review. A passing automated scan is not a published update.

The catalog's install command is:

```sh
omarchy plugin add https://github.com/OBJLAKO/omarchy-lofi-focus.git --enable
```

It obtains current upstream files. Keep the README's pending-review wording
accurate until the marketplace publishes the newer snapshot; then replace it
with a link to the actual updated listing.

## Visual assets

| Asset | Role |
| --- | --- |
| `docs/showcase/skylofi-v3-cover.png` | README launch cover |
| `docs/showcase/skylofi-v3-social.jpg` | Small social-preview export |
| `docs/showcase/listen-demo.gif` | Listen navigation and playback controls |
| `docs/showcase/mix-demo.gif` | Nature layers and independent levels |
| `docs/showcase/settings-demo.gif` | Fades, dictation ducking and interface motion |

The cover is promotional artwork based on real interface references; its
[generation record](showcase/COVER-PROMPT.md) retains the prompt and references.
GIFs must render the actual current QML with isolated sample state, without
private data, installed-plugin state or network playback. The caption identifies
that scope.
Radio should never acquire a recording timeline just to make a demo more busy.

Keep each clip focused on one short task and allow its transitions to settle.
Text must remain readable at GitHub's displayed size. The README shows Listen
directly, with Mix and Settings in collapsible sections, so it does not show
three full-height demonstrations at once. Do not infer loading speed or audio
latency from scripted state changes in a clip.

Reproduce the controlled recordings from the repository root:

```sh
python3 tools/showcase_capture.py --clip all --output docs/showcase \
  --frames /tmp/skylofi-showcase-frames
```

The [capture driver](../tools/showcase_capture.py) needs the Omarchy/Quickshell
QtTest environment, D-Bus and ffmpeg. It exercises real controls in a copied
QML fixture with private temporary HOME/XDG directories, a private D-Bus with
service activation disabled, and fixed sample playback state. It starts no
decoder, reads no installed library and uses no network audio. Layer-shell
placement is replaced by an offscreen fixture surface.

Frames and capture logs stay in the selected temporary directory. The
[capture manifest](showcase/capture-manifest.json) records dimensions, frame
counts, command counts, GIF hashes and QML source hashes. These clips demonstrate
UI interaction and motion; their scripted state transitions do not measure
audio performance or demonstrate a successful remote extraction.
Current interface changes and focused validation are recorded in the
[3.0.1 polish report](POLISH-3.0.1.md); earlier performance reports retain their
historical alpha build identities.

## GitHub social preview

An image inside the README does not set the repository's social-preview image.
The documented workflow is **Settings → Social preview → Edit → Upload an
image**. GitHub accepts PNG, JPG or GIF below 1 MB and recommends at least
640 × 320 px, preferably 1280 × 640 px. Use the solid-background JPEG export:
it keeps the cover's 2:1 aspect ratio and fits the upload limit.
[GitHub social-preview documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

The JPEG is prepared for this separate Settings step; no completed social-preview
upload is claimed by its inclusion in the repository.

The documented repository REST update endpoint exposes description and homepage
but no social-preview upload parameter. Use the supported Settings workflow
instead of an undocumented browser endpoint; the cover is not automatically
uploaded by a commit or release. Repository settings access is required.
[Repository update parameters](https://docs.github.com/en/rest/repos/repos#update-a-repository).

Social preview controls link presentation on supporting platforms; it does not
promise discoverability, stars or search placement. Platforms may crop or cache
the shared image, so keep the title and essential interface reference away from
the edges and check the saved GitHub preview after upload.
