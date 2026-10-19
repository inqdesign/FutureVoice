# Review — series 03 · Say it again (다시 말하기, silent build) — 2026-10-14
Verdict: FIX

1. [visual] card 03 (`renders/03.mp4`, and the identical `~/Desktop/nawana-carousel-03-say-it-again/03.mp4`): the first frame is a blank white phone with the footer ("미래의 나 대답 중 · 건너뛰기") at partial opacity, and the screen is still empty at 0.3 s. That is the frame IG shows before playback and on every loop restart. Every other MP4 opens on a settled state, and status.md says the same of all of them ("loops open on the settled state, never blank"), which is not true of 03.
   → In `carousel.html` `prompter(c)`, do not open on `SA.blank(s); s._panel("lis")`. Open on the opener row already laid and settled, footer at full opacity: `SA.lay(s, 0); s._panel("lis"); SA.settle(s);`, or call `SA.answer(s, 0)` at t=0 and settle it, then keep `at(4300) SA.prompt(s, 1)`. Re-record 03 only (two loops, cut at the reset frame) and copy it over the Desktop `03.mp4`. The `03.png` poster is fine as it is.

Checked frames: renders/02.mp4 @0 1.5 3 4.5 6 7.5 9 10.15 · 03.mp4 @0 0.1 0.2 0.3 0.5 1.5 3 4.5 6 7.5 8.95 · 04.mp4 @0 1.5 3 4.5 6 7.5 9 9.95 · 05.mp4 @0 1.5 3 4.5 6 7.5 9 10.95 · 06.mp4 @0 1.5 3 4.5 6 7.5 9 10.92 · 07.mp4 @0 1.5 3 4.5 6 7.5 8.95 · 01.png · 08.png. Compared with `marketing/captures/say-again*.png`.

## What passed
- **Truth:** checked against HEAD `SayItAgainView` / `TalkCurriculum` / the ko catalog.
  - Every learner turn comes up. Corrected turns use "고친 대로 말해 보세요" with the fix highlighted and the note under it. The uncorrected turn uses "이 문장을 말해 보세요" with no highlight and no note.
  - The answers are the call's own lines.
  - "들린 말" appears only under 61, which is below `retryThreshold` 75. It is gone at 88.
  - "다시 시도" shows on every scored row.
  - The 92, 88 and 90 rows are green with a check. The 61 row is orange with a waveform. Both match `scoreColor`.
  - The finish line "3문장 중 3문장 읽음 · 평균 90점" checks out: (92+88+90)/3 = 90.
  - Only the two corrected lines are checked off in the Drill chapter. A take of 80 or more (`shadowMasteryScore`) masters a fix by `correctionId`.
  - The intro reads "3문장 · 2개 교정됨". The ko strings for the intro line, "미래의 나 대답 중", "건너뛰기", "말을 마치면 다음으로 넘어가요", "처음부터 다시" and "완료" match the catalog.
  - No countdown or timer appears anywhere. The cards never say "발음 점수" or "따라 말하기". No price appears except "첫 20분은 무료예요", which matches the 1200 s grant.
- **Fidelity:** all screens are kit components (`nw-bookpage`, `nw-sayagain`), and the flow is right: book cover → 다시 말하기 → intro → 시작 → read → answer → … → 완료 → book → 드릴.
  - Card 02's intro sits at the bottom with blank space above it. That matches the app capture.
  - The mid-run retry on 06 drops the later rows and replays the answer after the retried line. That matches the app's rejoin behaviour.
- **Voice:** ko is 해요체 throughout, with no 당신 and no em dash on screen (sweep plus frames) or in the captions. The fluent-self lines are casual and never longing. The story is the piece 01 interview talk, with went/told on the same past-tense point.
- **Visual:** every title is 2 lines and every description is 2 lines or fewer. Eyebrows run 01/08 to 08/08 in order. Nothing is clipped, and every colour is in the palette. The mosaic appears only inside the pill.
- **Channel:** all cards are 1080×1350. The MP4s are H.264 at 30 fps and run 9.0 to 11.0 s. IG has 5 hashtags in each language.
  - Threads (ko) is a reply under 02. It doesn't re-introduce nawana, points back once ("지난번 그 면접 통화"), and ties the two pieces together ("섀도잉이 한 줄이었다면, 이번엔 통화 한 통이에요"). It is about 240 characters with no hashtags and attaches the first 7 items.
  - The exported captions say nothing about turning the sound on. The "소리 켜고" lines are removed from IG and Threads, and card 04 has no hint drawn.
- **Safety:** no real user data or names, no testimonials. All scores, dates and counts are sample data.

## Suggestions (non-blocking)
- IG ko caption "상황 연습 장면도…": the app's tab is "상황연습" (no space). Change to "상황연습 장면도 같은 방법으로 다시 말할 수 있어요."
- Card 03 ko desc "고친 부분은 파랗게, **왜 고쳤는지**는 바로 아래에 있어요." The first clause has no verb. Better: "고친 부분은 파랗게 보이고, **왜 고쳤는지**는 바로 아래에 나와요."
- Card 05 ko desc "맞게 했던 말도 했던 그대로 나와요." repeats 했던. Better: "맞게 한 말은 한 그대로 나와요."
- en card 06 title "A score a line,\nretry any one" doesn't read as native English. Use copy.md's own fallback "Every line scored,\nretry any one" before any en render. Only ko is exported now, so this doesn't block.
- Card 05 already shows the 61 and "들린 말" in its feed, before card 06 introduces them. That is acceptable as continuity. If the founder wants 06 to be the reveal, run turn 4 in 05 at a score of 75 or more and keep 61 for 06 only.
- When the audio pass lands, restore the three sound lines status.md lists (card 04 hint, the IG ko/en lines, the Threads line), re-render 04 only, and re-review 04.

---

# Review round 2 — series 03 · Say it again (founder's reframe, HQ re-render) — 2026-10-14
Verdict: PASS (0 FIX)

Checked frames: renders/02.mp4 @0 3 6 8.9 · 03.mp4 @0 3 6 8.9 + last frame (seam) · 04.mp4 @0 3 6 8.9 · 05.mp4 @0 3 6 8.9 · 06.mp4 @0 3 6 8.9 · 07.mp4 @0 3 6 8.9 · 01.png. The Desktop export MP4s are byte-identical to renders/ (cmp). All files are 1080×1350, and the MP4s run 9.0 to 11.0 s.

## What passed
- **Round 1 item 1 is fixed.** Card 03 now opens on the opener row ("Hey, it's you…") with the footer at full opacity. Its first frame is no longer blank.
  - The loop seam cuts from the prompter back to the opener row. Every card resets this way, and the cut is acceptable.
- **The reframe is true to CLAUDE.md "Say it again" at HEAD `f5582a08`.** The claim is that what I meant is shown back fixed and fluent, and I say it again in the same conversation until it is mine.
  - `suggestion.alternative` is the learner's whole turn re-said, with their ideas in their order, so "하려던 그대로, 유창하게 고쳐져" holds.
  - The old "끝나고 나서야 떠올라요" hook is gone from the cards, the captions and Threads.
  - "내 것이 될 때까지 / 몇 번이고요" is backed by two features: Retry on every read line, and 처음부터 다시 for the whole run.
  - Both the cards and the captions keep the counterweight: lines you got right come up as said, so the whole conversation runs again, not just the fixes.
  - The answers are the call's own audio in the clone's voice. Only the corrected lines get checked off in the Drill chapter.
  - The UI labels match the ko catalog. "첫 20분은 무료예요" matches the 1200 s grant.
- **Voice:** Korean reads as written Korean in 해요체. There is no 당신 and no 따라 말하기. The "—" in carousel.html appears only in code comments, and nothing in copy.md or captions.txt has one. The English is native.
- **Visual:** every ko title is 2 lines and every desc is 2 lines or fewer, on all cards. Eyebrows run 01/08 to 08/08. Nothing is clipped, the colours are in the palette, and the mosaic appears only in the pill.
- **Channel:** IG has 5 hashtags in each language.
  - Threads (ko) is a reply under 02 (shadowing). It is about 244 characters with no hashtags and no sound line. It points back once and ties the pieces together with "섀도잉이 한 줄이었다면, 이번엔 통화 한 통이에요".
  - No sound line appears anywhere in captions.txt, and card 04 draws no hint.
- **Safety:** all data is sample data, and no real names or testimonials appear.

## Suggestions (non-blocking)
- Card 06 ko desc wraps "그 / 자리에서" across the line break. Option A: drop "그" and write "…보여 주고, 바로 다시 읽어요." Option B: break the line before "그".
- Threads paragraph 2, "내 차례마다 고친 내 말이 뜨고", implies every turn is corrected. The next paragraph fixes that. For a tighter version, write "내 차례마다 내 말이 고쳐진 채로 뜨고".
- Card 05 still shows the 61 and the "들린 말" line before card 06 reveals them. This is unchanged from round 1 and is a taste call.
- The en text block was not rendered in this export, because only ko ships. Render `?lang=en` for 06 and 07 before any en upload to confirm they still fit 2 lines.
