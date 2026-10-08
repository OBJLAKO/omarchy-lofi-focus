# Skylofi 3.5 showcase

These assets replace the earlier 3.0 promotional cover and GIFs in the public
README and marketplace preview. The earlier assets remain as historical records.

| Asset | Purpose |
| --- | --- |
| `cover.svg` | Editable code-native layout using the actual sound-space capture |
| `cover.png` | 1280 × 640 README cover; byte-identical to root `preview.png` |
| `social-preview.jpg` | 1280 × 640 social card, below GitHub's 1 MB upload limit |
| `sound-space.png` | Actual 3.5 shared-map QML render |
| `source-controls.png` | Actual 3.5 persistent Solo and live-control QML render |
| `mix.png` | Actual 3.5 scenes, room preset and source-card QML render |
| `capture-manifest.json` | Source snapshot and asset hashes |

The interface captures come from the final live-controls rendered review on
October 8, 2026, with a 480 × 620 fixture and the warm/teal theme. They use
isolated sample playback state and the real plugin QML. The layer-shell surface
is replaced for offscreen capture; no private library or installed settings are
read. No decoder or online stream is involved. The visible playback state is a
demonstration, not evidence of loading speed, audio quality or speaker latency.
Validation details are in the
[live-controls review](../../3.5-LIVE-CONTROLS-REVIEW.md).

The cover scales the complete, unmodified `sound-space.png` capture and places
it beside concise feature copy. Its surrounding background, type and decorative
lines are ordinary SVG layout. No generated or reconstructed interface elements,
fake star counts, performance badges or marketplace approval claims are used.

Rebuild the card with librsvg and ImageMagick:

```sh
python3 docs/showcase/3.5/render-cover.py
```

The script writes the README PNG, social JPEG and root marketplace `preview.png`.
The full card and a 640 × 320 thumbnail were visually inspected after rendering.
The title, focus message and main features stay readable at thumbnail size.

The JPEG is prepared for GitHub's separate **Settings → Social preview → Edit →
Upload an image** workflow. Its presence in this repository does not claim that
the social-preview setting has been changed. A commit does update the README
image and root preview submitted with a marketplace revision.
