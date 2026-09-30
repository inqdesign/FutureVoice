# nawana teaser reel (kinetic type, 1080×1920)

The same engine the v2/v3 teasers were rendered with (GSAP timeline on a page,
captured frame by frame with Playwright → ffmpeg), moved here from a session
scratchpad so it can be re-run. Only the SCRIPT section changes between versions.

    cat engine-head.html script5.js engine-tail.html > /tmp/nawana-reel-v5.html
    node render.mjs /tmp/nawana-reel-v5.html ~/Desktop/nawana-teaser-v5.mp4   # needs `npm i playwright`

- `script5.js` — v5: the fluent self speaks in the first second ("This is your
  voice. Speaking fluent English."), then record once → call yourself, the call
  with a correction, "No teacher. No stranger. Only you.", na·wa·na, end card. ~37 s.
- Pacing rule: a line holds ≥ 1.6 s after its last word lands.
