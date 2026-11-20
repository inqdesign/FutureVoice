# Review — 2026-11-20-scene-from-film — 2026-11-20

Verdict: PASS

Round-1 FIX resolved. The `nw-watch` kit now renders the two previously-English
chrome strings in Korean: the centred header reads **보는 중** (card 03/04, was
"Watching") and the primary end-bar button reads **교재로 공부하기** (card 04, was
"Study this"). Re-checked renders/03.png and renders/04.png — both read Korean,
and the fix matches the app's real strings. Nothing else regressed: dialogue
flow, bubble sides, speaker labels, title fit, card numbering (03/05, 04/05),
and palette are unchanged from the round-1 pass.

Checked frames: renders/03.png · renders/04.png (both re-rendered)

## Verified clean (carried from round 1, still true)

- **Truth.** Feature claim matches shipped commit 03ab3204 (scene from a
  film/series/play/book: the dialogue is that scene inside the story, the other
  person as their character, the learner opposite, no rehearsal talk). The flow
  shown — composer box → scene plays with counterpart as character + fluent self
  opposite → study bar — is the real behaviour.
- **Generated lines, not movie quotes.** Caption and Threads both say it plainly
  ("영화 원문을 외우는 게 아니라, 그 장면을 내 말로 다시 해보는 거예요" / "Not a
  movie quote to memorize — the scene, in your own words"). No real film/actor
  named, no verbatim quote; neutral invented scene ("running into an old friend
  at a café"), character "Theo", generated English lines.
- **Cost honesty.** No claim that Watch scenes are free or unlimited; only price
  shown is the correct "첫 20분은 무료예요" outro.
- **Supported languages.** "영어든, 앱이 지원하는 다른 언어든 똑같아요" — correct.
- **Voice.** Korean reads as native Korean, 해요체 throughout, no 당신,
  positive-first titles, no em dashes. English reads native. No hype.
- **Pixel font.** None in the marketing/type layer; only the app's own Futureself
  mosaic clipped in the outro pill. Pass.
- **Visual.** Titles fit two lines; scene bubbles wrap without clipping; key
  moment stays inside the card; first MP4 frame is filled, not blank; light
  palette + app-native blue; mosaic only clipped in the pill; card order 01→05.
- **Channel fit.** 5 items, 4:5 1080×1350, short MP4 loops; IG caption under
  2,200 with 5 ko+en hashtags; EN caption 3 hashtags; Threads ko ~230 (≤500).
- **Safety.** All names are kit sample data — no real user, testimonial,
  impersonation, or swipe at competitors.

## Suggestions (do not block)

- **Card 02 person-chip "Paige"** — neutral invented sample name, matches real
  app UI; acceptable as-is. Accepted in round 1.
- **"Future self" speaker label (cards 03, 04)** — kit-wide English convention
  left as-is in the ko locale dict (`core.js:48`), consistent with prior nawana
  carousels; out of scope for this piece. Accepted in round 1.
- **Caption/Threads "프로필 링크 / link in bio"** — generic wording is fine to
  ship; confirm the IG handle with the lead when CHANNELS.md fills in.
