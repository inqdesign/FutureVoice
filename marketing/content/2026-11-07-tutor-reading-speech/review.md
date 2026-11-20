# Review — 2026-11-07-tutor-reading-speech — 2026-11-07
Verdict: PASS

All six honesty traps the brief flagged are handled, and every claim traces to the code.

## Truth (verified against source)
- Feature is REAL, not overstated. `GoalPrep.swift:35-45` — `GoalPrepDay.script(.reading)`
  returns a `SpeechScript` with `genre: .explainer`; `TutorPicks.swift:313` returns a news
  article as a `SpeechScript` with `genre: .news`. Both land in the Speech tab's scripts
  list, read on the prompter and scored on the standard speech-take path. "튜터가 써 준 글을
  소리 내 읽고 점수를 받아요" is accurate.
- Score is code-computed, not AI-judged. Captions state it outright ("AI가 심사하는 게 아니라
  앱이 점수를 계산해 줘요" / "It's the app computing a score, not an AI judging you"). Matches
  CLAUDE.md ("Pronunciation is MEASURED per sound", `SpeechAnalyzer`).
- 81 shown ORANGE (under 85). Coach line is a positive, honest line, not a brag; alt text
  and captions label 81 / 94% / 148 wpm as kit samples.
- "첫 20분은 무료예요" is correct — `BillingConfig.freeTalkSeconds` defaults to 1200
  (`BillingConfig.swift:27`). No prices appear on any slide, so BRAND.md's stale Max line is
  not in play here.
- Reading + scoring free vs the talk grant are kept SEPARATE in the caption ("읽고 점수 받는
  데 플랜은 필요 없어요" then, on its own, "첫 20분은 무료예요"). No gate implied on reading
  aloud. Card 04's "내 녹음 듣기" is the learner's own take playback (free), not the paid
  "내 목소리로 듣기" voiceover.
- No trial language anywhere ("무료 체험" absent).

## App fidelity
- Screens are real `nw-speech` kit states (Scripts list, prompter, result). `nochallenges`
  strips the Challenges section; the own-script result has no rank sheet.
- Known/accepted compromise (brief risk 5), handled correctly: the custom interview script
  renders with the kit's "내 원고 / My script" genre tag, whereas a real tutor reading would
  show 설명 / 뉴스. The "tutor wrote it" meaning is carried by the slide text and script
  titles only; no sticker or caption points at the row tag. This is the documented, approved
  tradeoff, not a fabricated badge.

## Voice
- Korean reads as native written Korean, 해요체 on every label/desc, no "당신", positive-first
  titles. English captions/Threads read natively (written, not translated).
- No "—" em dash in any published string (the em dashes at carousel.html:72/167/189 are in
  CSS/JS comments only). Card text uses "·" middots and periods.
- Outro tagline is a reader instruction ("언어를 배우세요"), no longing; fluent self speaks no
  line in this piece.

## Visual
- No leaderboard/rank/competition anywhere (brief risk 6) — confirmed in all four MP4 frame
  pulls and both list/result stills.
- No text clipping of titles (all 2-line, within bounds); payoff lands inside card 04 (score
  reached by ~8 s). Card 02 highlights the interview row to draw the eye. Prompter top-edge
  fade is the intended stage mask, not a clipped frame. Palette is grid/ink/app-blue plus
  the app's own orange score, green metric, red record — all sanctioned.
- Card numbering consistent 01/06 … 06/06; mosaic clipped inside the pill on the outro.

## Channel fit
- IG carousel 6 items 1080×1350, 01/06 PNG stills, 02–05 8–12 s loops (≤60 s). Hashtags 5
  (ko) / 5 (en) — within 3–5. Threads ko ≈165, en ≈400 — under 500.

## Suggestions (non-blocking)
- The one soft spot is the "내 원고" tag on card 02's interview row vs the slide's "튜터가 써
  준". It's below the slide text and correctly un-stickered, so it holds — but if a future
  kit pass can render a custom script under an Explainer/News genre, cards 02 would read
  truer. No change needed to ship.
- Community series entry is still a lead decision (e20/e21 id collision with the
  2026-10-12 challenge piece, per copy.md open question 1). That's a separate `series.json`
  change needing founder approval and does not block this carousel upload.

Checked frames: renders/01.png, 02.png, 02.mp4 @4s, 03.png, 03.mp4 @2s 4s, 04.png,
04.mp4 @5s 8s, 05.png, 05.mp4 @3s, 06.png
