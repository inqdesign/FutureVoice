# Fidelity — building an app screen for the web (web/kit)

The website (`web/ko.next.html`) shows the iOS app's screens as live web components from a kit
(`web/kit/`). The founder's verdict on the first version: "the detail is poor — check the app one
screen at a time and build it exactly as it is." Your job is to make your assigned screens match
the real app as closely as a browser allows. Nothing invented: every element, size, colour, weight,
radius, spacing and string comes from the app (its SwiftUI source and its simulator captures).

## Files

- You own ONLY the screen files named in your assignment: `web/kit/screens/<name>.js`.
  Do NOT edit `web/kit/core.js`, `web/kit/nawana-ui.js`, `web/ko.next.html`, or any other file —
  other workers are editing other screen files in parallel, in the same working tree. No git
  commands that change anything (no commit, checkout, stash, reset).
- `web/kit/core.js` is the shared base: `NwScreen` (402×874pt screen scaled to the host width;
  `this.$`, `this.$$`, `this.sleep(ms)`, `this.sing(el)`, `this.typeInto(el,text)`,
  `this.countUp(el,to,ms,fmt)`, `this.beat(n)`, `this.t` = chrome strings STR.ko/STR.en),
  `icon(name)`, `esc`, `wordsHTML`, `IOS_CSS` (iOS colour variables), `<nw-futureself>` (the
  mosaic — a port of the app's Metal shader), `<nw-phone>`. Read it first. If something in core is
  wrong for your screen (an icon you need, a colour variable, the mosaic), do not edit core — say
  exactly what to change in your final report.
- Screens are authored in iOS POINTS: the shadow root's `.s` box is 402×874 and 1 CSS px = 1 pt.
  Use the app's point values directly (17pt body = `font-size:17px`).

## Sources of truth

1. The SwiftUI source in `/Users/eunggyuelee/FutureVoice/FutureVoice/Views/…` (and `Services/`
   for strings) — fonts (`.font(.body)` = 17pt regular, `.headline` 17 semibold, `.subheadline` 15,
   `.footnote` 13, `.caption` 12, `.caption2` 11, `.title3` 20, `.title2` 22, `.title` 28,
   `.largeTitle` 34), paddings, corner radii, colours (`.secondary` = #3C3C43 at 60% ≈ #8A8A8E on
   white, `.tertiary`, system fills: systemGray6 #F2F2F7, secondarySystemBackground #F2F2F7,
   tertiarySystemFill etc.), SF Symbol names, and the exact strings.
2. Korean strings: `FutureVoice/Resources/Localizable.xcstrings` (key = English source, `ko`
   value). The kit shows Korean chrome when the page lang is ko and English otherwise; learning
   material (conversation lines, scripts, words) stays English. Keep both languages working.
3. Simulator captures (1206×2622, iPhone 17). Keep them in `marketing/captures/<name>.png`.
   Captures: `scripts/marketing/capture.sh <capture-name> <out.png> [lang]` — the simulator is shared, so ask the lead first and never build/install yourself. If you need a state
   no capture shows, build it from the source and say so in the report.

## The loop

1. Add `static poses = [...]` and `async pose(name)` to your screen: put the screen straight into
   the state a capture shows (same texts as the capture, no animation). One pose per capture you
   match against.
2. Compare: `scripts/marketing/compare.sh <tag> <pose> <capture.png> <out.png> [lang]` renders the kit
   screen posed at 1206×2622 (status bar drawn by core) and writes capture | kit side by side.
   Read the output image and fix differences. Repeat until a side-by-side reads as the same app.
   Zoom into regions (crop with PIL) for fine detail — text weight, icon shape, spacing.
3. Icons: SF Symbols can't be loaded; draw them as inline SVG in your file (local `const`), traced
   to the symbol's real shape and weight at that size. Don't use emoji for UI glyphs.
4. Keep the animation: `demo()` must still play the scene (same beats `this.beat(n)` in the same
   order — the page's bullets are wired to those numbers), but every frame it passes through must
   look like the app. Keep the public methods the page and the carousel call (listed in your
   assignment). Keep `reset()` correct (demo loops).
5. Don't use requestAnimationFrame for scene timing (a video recorder runs on virtual time);
   `this.sleep` / CSS transitions are fine.

## Report (your final message)

- Per screen: the poses you matched, and a list of differences that REMAIN (with why).
- Any change you need in core.js (exact).
- Paths of your final side-by-side images.
