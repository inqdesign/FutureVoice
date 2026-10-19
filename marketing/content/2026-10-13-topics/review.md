# Review · 2026-10-13-topics (series 04, 내가 원하는 토픽) · 2026-10-14
Verdict: FIX

1. [fidelity|truth] card 05: the interviewer's line is labelled "Future self". Verified at HEAD:
   `ConversationView.swift:4665` passes `name: turn.role == .user ? "You" : "Future self"` to
   `DialogueLine` for every call, counterpart or not, so the kit is faithful and the APP is wrong
   (DialogueLine's own doc says "or a counterpart's name"). The copy "면접관과 통화가 시작돼요" /
   "you're on with the interviewer" then contradicts the bubble directly under it, and BRAND's
   whole point is that only the fluent self is you. Fix, in order of preference:
   (a) app: pass the call's counterpart name there (`counterpart?.name ?? "Future self"`, same in
   the "Future self is thinking…" row at :4857), ship it, then set the kit label to "Interviewer"
   and re-render 05; (b) if the post can't wait, re-frame 05 so the speaker label is never in
   frame (pan so the bubble's top edge sits just under the chip row, label scrolled above the
   window) AND keep the call title readable (item 2). Do not post 05 as rendered.
2. [visual] card 05 @8.5 s and poster 05.png: the call header "Job interview · panel round" is
   cut in half by the phone window's top edge; it is the only thing on screen saying this is the
   interview. Fix: `PAN.callChips` 175 → ~120 (and `PAN.callTop` check) so the title + "B2 >" row
   is whole in the final frame; re-render 05.mp4 + poster.
3. [truth] card 03: the eight "backend developer" topics are invented in the prompt's shape
   (status.md says so; carousel.html FIELD). Brief Risk 2 is explicit: real output only. Fix:
   run the app (or `PurposeTopicEngine` via a capture) with role "backend developer", paste the
   first eight titles it writes into `FIELD` verbatim, re-render 02 and 03 (02 shows them too).
4. [visual] cards 02/04: news captions render "Ai / Tech". It is app-faithful (`.capitalized`),
   but on a posted image it reads as a typo. Fix: change the sample interest from "AI / tech" to
   "technology" (renders "Technology") in NEWS0/NEWS1; re-render 02, 04.
5. [voice] Threads reply, line 2: "이번엔 무슨 얘기로 통화할지예요." is not Korean (noun-clause +
   예요). Replace the sentence with: "이번엔 무슨 얘기로 통화할지예요" → "이번엔 무슨 얘기로
   통화할지 내가 정해요." Update copy.md and ~/Desktop/nawana-carousel-04-topics/captions.txt.

Checked and fine
- Truth: chips = purpose chips in picked order, then News, then Scenarios
  (`LearningPurposeStore.chips`); 8 shown, refresh walks/grows the pool (`PurposeTopicEngine.shown
  = 8`), so "새로고침하면 더 나와요" is true though not shown (acceptable, said not shown);
  "이번 주" matches the app's own footer ("이번 주 기사"); scenario chips from the book are
  `TalkGoalPicker.pick(forScenario:)`; ko loading row "내 분야 주제를 만드는 중…" is the catalog
  value; "첫 20분은 무료예요" matches. No trial/unlimited/flame/missed-call claims.
- Overlap with learning-purpose: no "왜 배워요" picker, no starter lists on any card.
- Voice: 해요체, no 당신, no em dash in copy.md / captions.txt (0) and the rendered screens are
  swept (`undash`); "아무 얘기나" only on 06 (the ring). Titles ≤ 2 lines on every card.
- Channel: 1080×1350 all items; MP4s 8.6–10.5 s; IG hashtags 5 each; Threads ≈250 chars, no
  hashtags, written as a series reply (no re-intro). series.md row 61 lists this as 04 under 03
  say-it-again, matching "03 아래 답글".
- Safety: no real names; "Sarah (close friend)" is a fictional kit sample; news neutral.

Suggestions (non-blocking)
- 05 @2.5 s is a mostly blank white call body (chips only) for ~1.4 s; shorten the
  `k.sleep(1400)` before the opener to ~700 ms.
- 04 @5 s: blank call sheet for a beat before the opener; same trim.
- "칩에는 그 상황에서 익히던 말이 떠요" → "칩에는 그 상황에서 익히는 중인 말이 떠요" reads a
  touch more natural.

Checked frames: renders/02.mp4 @0 2.5 5 8.5 s · 03.mp4 @0 2.5 5 8.5 s · 04.mp4 @0 2.5 5 8.5 s ·
05.mp4 @0 2.5 5 8.5 s · 06.mp4 @0 2.5 5 8.5 s · 01.png · 05.png (poster)
