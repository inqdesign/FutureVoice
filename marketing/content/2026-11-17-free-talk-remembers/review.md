# Review — 자유 대화가 지난 대화를 기억해요 (1.3.6 / build 149) — 2026-11-17
Verdict: PASS

No FIX items.

## What was checked and passes

- **Truth.** Claim matches CLAUDE.md "A free talk remembers the talks before it, and the
  APP looks one up" (`TalkRecall.swift`): bring up a past talk, the app looks it up, the
  fluent self continues from what was actually said. Free-talk-only is kept everywhere
  ("유창한 나와의 자유 대화에서" / "Free talk with your fluent self"); no scenario / Find
  people / tutor contamination. "없던 통화는 지어내지 않아요 · Only the ones you really made"
  correctly mirrors the "I don't remember that one, tell me" fallback — no omniscient
  "remembers everything" promise. No scoring/feedback framing (copy forbids correction,
  score, coach panel). The payoff line "You were sweating the portfolio question" reads as
  the fluent self recalling the learner's OWN earlier words (nervousness about the portfolio
  question was in the past talk per brief), not omniscience — believable.
- **Price.** "첫 20분은 무료예요 / Your first 20 minutes are free" verified against
  `BillingConfig.freeGrantSeconds` = 1200 s (and `FreeRecharge` 1200). No "무료 체험" used
  (no trial). No other prices shown.
- **App fidelity.** 02–04 are one `nw-call` free-talk screen, three moments of the same
  conversation; no invented "memory list" UI (index/lookup are background, no UI). Labels
  "미래의 나" / "나", the thinking line "유창해진 내가 생각하는 중…", and the bottom hints
  are the kit's real Localizable ko strings (`web/kit/screens/call.js`) — authentic, not
  drawn. Bubble material stays English both versions; no in-app word-highlight faked.
- **Voice.** Korean reads as native Korean, 해요체 chrome on every title/desc/caption, no
  당신. Fluent-self lines are casual English ("No way, that's huge"), no longing. English
  captions/Threads read native. No em dash in any caption / Threads / community text
  (middots only). Hashtags 5 ko / 5 en (within 3–5). Threads ko ~200 and en ~380 chars,
  both under 500. IG captions under 2,200.
- **Visual (PNG keyframes).** Text blocks legible; all titles ≤ 2 lines; descs ≤ 2 lines,
  no overflow/clipping; key moment of each card inside the card; cover works as a still
  (faint call behind title); outro standard (Futureself pill clipped, light palette,
  wordmark · 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app). Palette within
  ink/blue/grid + kit's own bubble colours. Card numbers consistent 01/05 … 05/05. Bold
  sans title block is CORRECT per the founder's 2026-11-13 directive (not a defect).

## Suggestions (non-blocking)

- Card 03 is meant to be the strongest card with "design studio" / "the portfolio question"
  emphasized. The render relies on the desc's bold ("실제로 오갔던 말") only; the in-phone
  bubble is plain. Not faking an in-app highlight is the right call for fidelity, so leave it
  — but if more punch is wanted, emphasize outside the phone (desc wording or a sticker),
  never inside the bubble.

## Note on coverage

MP4 frame extraction (ffmpeg/bash) was unavailable in this environment. Verified instead
against the recorded PNG keyframes (02.png/03.png/04.png = the payoff moment of each MP4)
and the exact authoring in `carousel.html` + `web/kit/screens/call.js`. The authoring shows
only a ~0.65 s empty-feed transient at each loop start (nav bar + pill + hint still present,
feed area empty) before the user bubble types in; the PNG stills used for the grid/cover
positions are the populated state. If a human can eyeball 02–04 before posting, confirm the
exported first frame isn't that empty-feed instant — otherwise no concern.

Checked frames: renders/01.png · 02.png · 03.png · 04.png · 05.png (MP4 timecodes not
extractable here; verified via these keyframes + carousel.html/call.js authoring)
