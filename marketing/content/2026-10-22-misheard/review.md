# Review — misheard (1.2.2 / build 118) — 2026-10-22

Verdict: PASS

All six cards, both IG captions, both Threads texts, and the carousel HTML
check out against the app, BRAND.md and the three critical checks.

## What was verified

- **Truth / feature fidelity.** The marketed control is real in build 118.
  `DrillSheet.swift:900-928` pins a plain (non-destructive) `ellipsis.circle`
  menu to the review card's `.topTrailing` corner with ONE item,
  `Label("Misheard — exclude from scoring", systemImage: "mic.slash")`; the
  comment confirms "red text on the menu read poorly (2026-10-22, founder)"
  and "pinned to the card's corner ... whatever the sentence's length".
  `markMisheard` (`:1211`) excludes the turn from scoring, reassesses, deletes
  the turn's cards, removes them from the deck run and logs no rep — exactly
  what cards 03-05 claim. Korean catalog label is `잘못 들림 — 채점에서 제외`
  (verbatim in `Localizable.xcstrings`); the card-04 toast text
  ("채점에서 빠졌어요 / 여기서 나온 카드도 정리됨") is a true description of
  that behaviour.
- **Critical check 1 — the "You said" sample reads as an STT mishearing.**
  "Feel something around Nirvana the app that I'm gonna be working on" is the
  kit's own garble (recognizer heard "nawana" as "Nirvana" and mangled the
  opening). It reads as machine mis-hearing, not a learner grammar error.
  PASS.
- **Critical check 2 — the ⋯ / misheard control is calm.** Card 03 (and the
  ⋯ on cards 01, 02, 04, 05): `ellipsis.circle` in the card's top-right
  corner; the open menu is a black title "잘못 들림" + grey subtitle
  "채점에서 제외" + `mic.slash`, no red, no warning tone, one item. PASS.
- **Critical check 3 — cards 03-04 use the menu + a cleanup toast, not a
  fabricated card-slide.** Card 03 opens the real menu; card 04 shows a
  green-check confirmation of the tap the learner made in 03. It is honest
  (states what the user's own action did) and never implies auto-detection —
  the learner taps first. PASS.
- **Em dashes in posted text.** None. The real label's em dash
  (`잘못 들림 — 채점에서 제외`) is correctly split on the slide into title +
  grey subtitle (card 03). grep of `copy.md`/`carousel.html` finds `—` only
  in internal headings/comments and the HTML doc panel (`<h1>`, line 235) —
  never in a slide value, an IG caption body, or a Threads body.
- **Prices / limits.** Only free-time claim is "첫 20분은 무료예요 / First 20
  minutes free" on the outro (card 06). No other price or limit claim; matches
  BRAND.md.
- **Voice.** ko reads as native 해요체 throughout, no 당신, conversational
  ("…보일 때 있죠", "그게 다예요", "공정하게, 내 손에서요"); en reads native.
- **App fidelity.** The deck subtitle "1 / 20 · 6명 대기 중" that looks odd is
  the app's own real string (`" · %lld waiting"` → ko "· %lld명 대기 중"), so
  it is faithful.
- **Channel fit.** 6 cards at 4:5; MP4 durations 5-10 s (≤60 s); Threads ko/en
  both well under 500 chars; 5 hashtags each.
- **Safety.** No real user data/names, no testimonials, no impersonation, no
  claims about other products.

## Suggestions (non-blocking)

- Card 04's cleanup toast is drawn inside the phone frame as if it were app
  chrome; the real app just animates the cards out with a haptic (no toast).
  It's honest and lead-sanctioned as the storytelling device, so it passes —
  but the strictly-faithful option is the deck's own file-away motion (as the
  copy originally specced) or the toast as a sticker outside the frame.
- Card 01's cover sticker strikes only the middle line of the sample; in-app
  the whole "You said" line strikes on reveal. Decorative cover sticker, calm,
  fine — a full strike would read marginally more like the real state.
- Episode id is still `TODO` in copy.md; lead to confirm e22 (vs e20
  accent-words / e21 coach-suggestion) before the publisher drafts the series
  entry. Does not block the carousel or captions.

Checked frames: renders/01.png · 02.png · 03.png · 04.png · 05.png · 06.png;
renders/03.mp4 @0.2s 4s; renders/04.mp4 @0.2s 5s; renders/01.mp4 @0.2s
(durations 01=5s, 03=9s, 04=10s).
