# Review — 2026-11-09-weekly-test-your-week — 2026-11-09
Verdict: FIX

1. [channel|copy] Threads (en) is **514 chars**, over the 500 limit (copy.md self-labels it "≈ 490" but it measures 514). Trim ~15+ chars, e.g. drop "simply" and shorten the opener ("You talk and flip review cards all week, then the test pulls from someone else's workbook. Deflating." / cut "A thin week simply doesn't open it." to "A thin week doesn't open it."). Threads (ko) is 262 — fine. Owner: copywriter.

## Checks that passed (for the record)

- **Truth.** Every verbal claim holds against CLAUDE.md "The weekly test (redesigned 2026-11-08)":
  built only from that week's material (02: fluent-self phrase in the gap; 03: corrected sentences + lines worth hearing again); a thin week doesn't open the test (03 note, matches `minItems`); a right answer is known everywhere — card 04 copy says "단어와 문장" (meaning→markKnown, gap→known expression, translate→card retires), which is exactly the set that writes known (grammar/listen/speak/upgrade write nothing, and the copy does not claim them); appeal "제 답도 맞아요" (05) = `WeeklyTestAnswer.appealed`, told in copy only with no button mockup. No streak flame, no score gauge on any card (kit `nw-weeklytest` enforces it; result page has neither). "첫 20분은 무료예요 / Your first 20 minutes are free" matches the 1200 s free grant, no trial.
- **App fidelity.** Every screen is the real kit `nw-weeklytest` on the `interview` sample; labels are the app's own (주간 테스트 · 빈칸 채우기 · 자주 틀리는 문법 · 영어로 말하기 · 잘한 한 주예요 · 틀린 것 · 이번엔 아니에요 · 틀린 것 다시 풀기). 04 shows the result page (score 6/7 sample, one missed row back in review); 05 shows a genuine wrong verdict where the appeal lives. No fabricated screen, no standalone appeal screen (cards 04/05 are text-only for known-everywhere and appeal).
- **Voice.** Korean is native 해요체, no 당신, titles positive-first; English reads native (not a gloss — e.g. "The blank wants a phrase the fluent you used"). No em dash in any caption / Threads / news draft (verified).
- **Visual.** Renders are 1080×1350, H.264, 30 fps, 8–12 s loops. First frames are the full wide state (phone whole, no blank/half-fade); zoomed moments land inside the card with no clipping or overflow; titles fit two pixel lines; palette stays ink/blue with app-semantic green/red; Futureself mosaic is clipped inside the outro pill (not a background). Card numbers 01–06 consistent.
- **Channel.** IG caption ko 279 / en 572 chars (≤2200), 5 hashtags each, first line is the hook. Durations ≤ 60 s. Community is a NEWS draft (not a new series entry — e16 already covers the feature), per brief.
- **Safety.** No real user data, no founder name, no invented testimonials; all on-screen numbers/scores are kit sample data.

## Suggestions (non-blocking)

- Card 03 draws a `grammar` item. The 2026-11-08 redesign that this piece markets retired `grammar` (and `build`/`upgrade`) from the freshly-dealt set — only translate · gap · meaning · listen · speak + last-week retakes are dealt now ("papers on disk still play them"). It is still a real renderable app state and the launching brief/task explicitly list grammar as a valid kind, so this is not a block — but for a piece about that exact redesign, a `translate` screen (which card 05 already uses) depicts how a correction is currently tested (the pattern in a NEW sentence). Note the card-03 copy "그대로 문제가 돼요" fits grammar/build's verbatim-own-sentence mechanic more than translate's new-sentence one; consider for a future refresh.
- Version tag: brief.md and copy.md headers say build 136; this upload is build 137. Update the metadata line (not on any card).

Checked frames: renders/01.png · 02.mp4 @0.2s 2.5s 4s · 03.mp4 @0.2s 6s · 04.png @3s · 05.mp4 @0.2s 6s · 06.png
