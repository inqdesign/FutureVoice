# Review (round 2) — coach-suggestion (1.2.2 / build 117) — 2026-10-22

Verdict: PASS

All three round-1 FIX items are applied correctly; regression pass found nothing new.

## Round-1 fixes — re-checked

1. [visual] card 05 em dash — FIXED. Source (`PLAY.hand` → `s.say(...)`) now reads `Do it this weekend. Treat yourself.`; confirmed on the rendered reply bubble (05.mp4 @8s). No em dash.
2. [visual] card 04 pointer — FIXED. The `.point` sticker ("내 얘기가 그 자리에") sits outside the phone frame at bottom-left and its arrow now curves up to the underlined own-fact span `the one in Sinjeon` in the suggestion line, not the mic-pill mosaic (04.mp4 @4s, 04.png). The underline stays the only app-screen highlight — nothing drawn onto the screen.
3. [visual] accent blue — FIXED. `--blue:#0A5CF5` (was `#0A84FF`); no `#0A84FF` remains. `--ios-blue:#007AFF` is the app screen's internal iOS blue (correct, expected). Blue reads consistent on the series square, card-04 pointer, cover lightbulb and outro `nawana.app`.

## Regression pass — clean

- Sizes: all 6 outputs 1080×1350 (01/02/03/04/05/06). Durations 8/8/9/11 s (all ≤ 60 s).
- Frame-0: 02/03/04/05 first frames are complete seeded screens (no blank/pre-animation frame-0). Card 04's arrow is a timed reveal (absent at 0s, in by ~1.1s) — intended, screen content is full.
- Highlight: underline (faded gray) is the only app-screen mark on 03/04/05; the emphasis pointer is a sticker outside the frame.
- Em dash: none in any published surface — IG captions (ko/en), Threads ko, and all rendered card text are clean. The `—` occurrences that remain are internal only (brief.md intent notes, copy.md section headers/screen notes, carousel.html `<title>`/side-panel `<h1>`/JS comments) and none render into a card or a posted caption.
- Price/free: only `첫 20분은 무료예요 / First 20 minutes free` (outro + captions). No price figures.
- Truth/fidelity/voice unchanged from round 1 (no copy edits beyond the three fixes): claims match CLAUDE.md "Coach mode", 해요체, no 당신, no hype, real `nw-call` coach pose, Sinjeon demo is kit sample data.

## Suggestions (non-blocking, carried from round 1)

- On-screen app label `이렇게 말해 보세요` (해요체) vs headline `이렇게 말해 봐` (반말) sit side by side on card 02 — defensible (the fluent self speaks 반말), worth a lead glance.
- Episode id `e21` vs the accent-words piece's `e20` — publisher to confirm with the lead before the series entry.

Checked frames: renders/01.png · 06.png · 02.mp4 @0s 3s · 03.mp4 @0s · 04.mp4 @0s 4s · 05.mp4 @8s 10s · 02/04 .png stills
