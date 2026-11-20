# Review — 2026-11-03-sync-devices — 2026-11-04

Verdict: PASS

Reviewed end-to-end for 1.2.9 (131). Zero FIX items. The one flagged question
(card 05 letter avatars vs photos) is ruled an acceptable visual proxy — reasoning below.

## Truth — all claims hold
- Opt-in is never hidden: card 01 "켜 두면", card 05 "켜는 건 내 선택", caption
  "Me → Devices에서 켜고". Nothing reads as on-by-default. ✓
- "내 iCloud로만 가요. 우리 서버엔 아무것도 올라가지 않아요" / "stays in your own
  iCloud, and nothing lands on our servers" — matches CLAUDE.md "Sync…" verbatim. ✓
- Card 02 routine + reminder times sync → CLAUDE.md "the routine with its promise
  days and rep times", StudyPlan synced 2026-11-03. ✓
- Card 03 "복습하면 폰 덱도 같이 줄어요" → "a review on the tablet moves the phone's
  deck". ✓
- Card 04 word + state (studying/known/used) as one list → word/expression records
  + membership sync. ✓
- Card 05 faces, speech speed, voice pick → "people's photos, the profile photo …
  speech speed, the fluent self's voice pick". ✓
- No over-claim on audio: caption/cards never assert audio always syncs (blobs are
  Wi-Fi-only) — correctly left out. ✓
- "첫 20분은 무료예요 / First 20 minutes free" = 1200 s free grant
  (twenty_free_minutes). ✓ No prices shown.

## App fidelity
- Every screen is a live kit component (web/kit/nawana-ui.js): nw-home, nw-routine,
  nw-review→book→drill, nw-words, nw-people. ✓
- Hard constraint honoured: the Me → Devices / sync surface is NEVER drawn; sync is
  said in text only. No toggle, no device list, no invented screen. ✓
- Flows are real (review shelf → book → drill chapter on 03; people→situations on 05). ✓

## Voice
- Korean: 해요체, native, positive-first, no hype, no rationale, no "당신" anywhere. ✓
- English: native. Card 01 British "Practise" is consistent with the en-GB store
  locale — intentional, not a slip. ✓

## Visual (frames read)
- Titles all 2 lines, card numbers consistent 01/06 … 06/06. ✓
- Palette: blue + iOS system only. Futureself mosaic appears only as the outro brand
  pill and clipped inside the home ring (card 01) — never as a background. ✓
- No blank/half-faded first frame, no text overflow or clipping in any extracted
  frame; key content on screen throughout each loop. ✓

## Channel fit
- 6 × 1080×1350; durations 3 / 9 / 12 / 8 / 12 / 3 s — all ≤ 60 s. ✓
- Hashtags: ko 5, en 5 (within 3–5). ✓  Threads ko = 217 chars (≤ 500). ✓

## Safety
- Only kit demo names (Sarah/Mark/Lena/Jun); no real user or founder data, no
  testimonials, no impersonation, ring/word numbers are samples. ✓

## Card 05 letter avatars — ruled ACCEPTABLE proxy, not a FIX
The headline foregrounds photos ("사진·설정까지 / Even photos"), while nw-people shows
S/M/L/J initials, and the loop pans past the people row to situation cards by ~6 s.
Not a false visual promise, because:
1. Photos genuinely sync (CLAUDE.md 2026-11-03) — the claim is true.
2. The sync surface cannot be drawn (status.md hard constraint), so the photo/settings
   claim lives in TEXT and a representative practice screen stands in — the piece's
   whole sanctioned approach.
3. The kit renders initials BY DESIGN ("PersonBubble without a photo", people.js:134):
   that is a real app state (a person with no photo yet), not an invented drawing, so
   it stays app-faithful. The initials assert nothing about what does/doesn't sync.

## Suggestions (non-blocking)
- Card 05 is the weakest copy↔visual pairing: a photo-led headline over a
  faces-absent screen whose loop scrolls to Watch situation cards unrelated to
  photos/settings. Acceptable as above, but if the kit ever gains a real face, use it
  here — or lead the headline with people/settings rather than "사진/photos".
- Card 04 EN "…stay one list across your devices" reads slightly loose; "stay on one
  list" or "are one list" would be cleaner. Understandable as-is, not blocking.

Checked frames: renders/01.png (still) · renders/02.mp4 @0.1s 5s · renders/03.mp4
@0.1s 6s 10s · renders/04.png (still) · renders/05.mp4 @0.1s 6s · renders/06.png (still)
