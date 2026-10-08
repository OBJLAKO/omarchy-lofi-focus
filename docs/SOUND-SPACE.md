# Build an atmosphere

In **Mix**, select a sound card to open its three main controls. **Volume** sets
its level, **Distance** moves it near or far, and **Coverage** spreads it from a
point into a wide or surrounding stereo texture. These controls are independent:
a distant rain can still surround you, and a nearby fire can stay compact.

**Nearby**, **Distant** and **Around** provide starting placements without
changing the volume. Adjust them by ear: every slider applies while it moves.
**Solo** is visible on every sound card and isolates that active layer while
the mix is playing. It stays on while you change its volume and acoustics;
**Back to mix**, Pause or Stop ends isolation immediately. The normal mix also
returns if the source disappears or a different scene is applied.
The room's existing reflection tail can linger briefly after isolation begins.
Solo listening never changes your saved levels or resumes stopped audio.
The Mix view names the isolated sound and provides **Back to mix** even when
you select a different card. Start playback first if Solo is unavailable.

**Edit overall space** replaces the cards with a shared map. Drag a source icon
left/right or near/far; arrows make small adjustments. Picking an icon changes
selection only. When several sources occupy the same position, the icons spread
out visually and thin lines show their real locations. This keeps every source
selectable without changing its audible placement. Coverage changes the shaded
zone continuously, so a point stays compact and a surrounding field fills the
map.

Choose one room preset, then use **Room acoustics** or **Extra acoustics** only
when more detail is useful. Outside boundaries muffle a source; reflections and
echo add depth. **Living mix** changes unlocked levels slowly below the fader's
chosen level. Turn off **Vary this sound** for an anchor that should stay steady.

## A fire near you, rain around you

1. Add Fireplace or Campfire, choose **Nearby**, then place it a little to the
   left or right. Keep Coverage near 10–20% and choose a comfortable level.
2. Add Rain, Window rain or Soft drizzle. Choose **Around**, then set Distance
   around 60–85% if it should feel farther away. Outside the room is useful for
   rain behind a window.
3. Add Wind in leaves with Coverage around 60–70% and a different side or
   distance. Keep its level below the fire and rain.
4. Pick a warm room preset, enable a gentle Living mix if desired, and save the
   scene. Isolate each sound briefly when adjusting its placement.

## What surrounding means

Coverage uses a fixed stereo diffuser, including for mono input. Headphones make
the separation easier to hear; speakers depend on their placement and the room.
It creates an enveloping stereo impression and does not provide measured HRTF
front/back positioning, personalized ear profiles or head tracking. The map's
vertical axis denotes distance, rather than a physical direction behind you.

The Rust implementation keeps fixed short delay buffers, smooths changes, and
shares the room's reverb and echo buses. It adds no decoder process or downloaded
sound data. Broadening uses a convex direct/diffuse mix to avoid increasing
correlated low-frequency gain; broadband textures may become a little quieter.
Per-source diffusion histories reset when a slot receives a different source.

Prior scenes migrate their old stereo width into Coverage once. Original
stereo width remains an advanced control for existing material. Volume,
distance, left/right position, soundtrack and playback intent are retained.
