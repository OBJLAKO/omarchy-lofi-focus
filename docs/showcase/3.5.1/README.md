# Skylofi 3.5.1 artwork

`cover.png` is the 1600 × 900 marketplace preview. `cover.svg` is its editable
composition, using the unmodified QML captures `mix.png` and `sound-space.png`.
The sample scene contains lo-fi radio, rain and a fireplace; no private library
data is shown. The screenshots demonstrate stereo spatial controls.

To render the cover and refresh the repository's `preview.png`, install
librsvg's `rsvg-convert` and run:

```sh
python docs/showcase/3.5.1/render-cover.py
```

The text uses Adwaita Sans (with a sans-serif fallback). Use Adwaita Sans when
reproducing the supplied render. Keep the screenshots alongside the SVG so its
relative image references resolve. Source PNG captures render the real interface;
the SVG adds only the background, typography and shadows.
