# Brief · series 06 · 위클리 테스트 (Weekly test)

Strategist, 2026-10-13. Intent only; copywriter writes ko and en natively. Source: community e16
"주간 시험 · 일주일 동안 배운 것만으로 만든 시험지" (10 slides: 매주 한 번 내 시험지 · 뜻 보고 단어
고르기 · 빈칸에 표현 · 고친 문장 조립하기 · 듣고 받아쓰기 · 소리 내 말하기 · 틀린 건 다음 주에 다시 ·
한 달 치 오답은 월간 시험으로 · outro). Keep the good beats, drop what is no longer true:
**"고친 문장 조립하기" (build) is no longer dealt** (replaced by translate: your mistake's pattern
in a NEW sentence), and **there is no monthly test** (misses come back inside the weekly one).
Carry-overs fixed: light theme, kit only, eyebrow "nawana · NN / 08", ONE story, no em dash,
Threads reply.

## One message

**공부는 했는데 남은 게 있는지 모르겠을 때, 내 한 주로만 만든 시험을 봐요. 이번 주 통화의 단어와
표현, 그리고 내가 틀린 문법을 새 문장으로 다시 물어봐요.**

(en intent: a test made only from your own week: the words and phrases of your calls, and your
own mistakes asked again in a sentence you haven't seen. Nothing from a generic bank.)

## Who it's for

The learner who has been talking for a week (the interview week) and wonders if any of it stuck.
Has tried app quizzes that test words they never met. Not a beginner.

## Why now

- Series 06. 05 showed words moving from call to call; 06 is the check at the end of the week.
- The translate item (2026-10-08) is new since e16 and is the most "only here" thing on the
  paper: the mistake from piece 01 ("it go" / "tell") comes back as a different sentence.
- e16 carries two dead claims (build kind on its own slide, the monthly test). The community
  entry needs replacing either way.

## The story (the interview week)

- Meaning: "perspective" (the book's Words chapter, still unmastered; NOT "compelling", which
  05 shows being used, and used words are dealt last). Decoys: same-class words (nouns).
- Gap: the shadowing line of 02 with the fluent self's phrase blanked: "You clearly _____ and
  prioritized what mattered." → took the initiative (decoys: the week's other phrases).
- Translate: the past-tense slip of piece 01 in a new sentence. Native prompt, sample "어제 면접관이
  다시 전화했어." → "The interviewer called me again yesterday." Tiles + decoys from the learner's
  own mistake ("call", "calls"). After: the point (과거 시제) + "지난번엔 이렇게 말했어요: it go → it
  went". (Prompt sentence must be real output, see Risks 2.)
- Listen: "You clearly took the initiative and prioritized what mattered." heard, text hidden,
  rebuilt from its own tiles (same line as 02, its audio already exists).
- Result: 6 / 7 "잘한 한 주예요", one miss (the gap), "These are back in your review, due now".

## Proof in the app (HEAD code)

- Opens at the learner's chosen time (default Saturday 10:00, `WeeklyTestSchedule`); the door is
  the Review page header: the test host's face with a dot (`WeeklyTestView`, route
  `.weeklyTest`); also a routine block. Material window = since last test, else 7 days; under 5
  items it says the week is thin.
- Kinds (`WeeklyTestEngine`): meaning (word from the week's talk BOOKS' Words chapters), gap
  (an Expressions "To study" phrase in the line it was heard), translate (up to 3, one per
  grammar point, from correction cards + recurring mistakes; native sentence → tiles; code grades
  the order, one natural-reorder check by a small model), grammar + upgrade (from the week
  report's coach: series 07), listen (fluent-self line, text hidden, rebuild), speak (said out
  loud, scored like shadowing, pass 75).
- Every grade is computed in code; no model decides right/wrong except the narrow reorder check.
- The host: two pixel eyes; happy on right, sad on wrong, a brief pout on a second wrong.
  Sound + haptic per answer. **No flame, no gauge** (BRAND; the result is a headline + "N / M").
- Misses come back: the last 4 papers' wrong answers, up to 5, newest first, badge "Again"
  (`isRetake`); one asked again and answered right is done. Result screen: missed list, "These
  are back in your review, due now", "Try the missed ones again".
- Write-back is a claim: meaning right → word waits 3 days, wrong → back in the notebook due now.

## Outline · 8 cards (eyebrow "nawana · NN / 08")

**01 · Cover (still).** Problem: 공부는 했는데, 뭐가 남았는지 모르겠어요. Answer, bold: 내 한 주로만
만든 시험. `nw-futureself` circle + chips (토요일에 열려요 · 이번 주 단어 · 유창한 내 표현 · 내 실수를
새 문장으로 · 듣고 맞추기 · 틀린 건 다시).

**02 · 매주 한 번, 내 시험지.** Say: once a week, at the time you chose, a paper made only from
your week. Screen: `nw-book` Review header, the host face with its dot pressed → `nw-weeklytest`
sheet opens on item 1/7, the host blinks. Poster: the opened paper. Kit gap 3.

**03 · 이번 주 통화에서 나온 단어.** Screen: meaning item, prompt = the gloss of "perspective", four
nouns, tap → right → host happy, green bar. Silent.

**04 · 유창한 내가 쓴 표현, 빈칸에.** Screen: gap item "You clearly _____ and prioritized what
mattered." → took the initiative → right. Silent.

**05 · 내가 틀린 문법, 새 문장으로.** The signature card. Say: it doesn't ask the sentence you got
wrong again; it gives the same point in a new sentence, with your old mistake as trap tiles.
Screen: translate item, Korean prompt → tiles laid (decoy "call" left in the tray) → right →
point + "지난번엔 이렇게 말했어요 · it go → it went". Poster: the explanation state.

**06 · 듣고, 그대로 맞춰요.** Say: your fluent self's line from the week, heard, text hidden,
rebuilt from tiles. Screen: listen item, play pressed, tiles laid in order. **Sound: Audio A**
(reuse piece 02's clone take). Optional: swap for speak if the founder prefers.

**07 · 틀린 건, 다시 나와요.** Say: the result says what you missed; misses go back into review now
and return in next week's paper. Screen: result 6 / 7 "잘한 한 주예요", missed row (the gap), the
footer line → cut to next week's paper: the same item with the "Again" badge. Poster: result.
Kit gap 1. No flame, no gauge.

**08 · Outro (unchanged).**

## Audio

- **A · reuse** `2026-10-13-shadowing` Audio A (founder's Cartesia clone, "You clearly took the
  initiative and prioritized what mattered."). No new take. Card 06 only.
- Everything else silent. The app's answer sounds (four synthesized UI cues,
  `scripts/make-ui-sounds.py`) could ride on 03–05 if the designer wants; ask the founder (it
  would be the first piece with UI sounds).

## Kit gaps (mkt-web)

1. No "Again" retake badge on the item caption line (`WeeklyTestView`, caption2 capsule,
   tertiary fill). Needed for card 07.
2. Sample items aren't the interview week: meaning gloss/options, gap line, translate (startup /
   two years), listen tiles (push back on). Needs story items as above (or an `items` input).
3. The Review header face (`nw-book .ts`) has no press method and no sheet transition into
   `nw-weeklytest`.
4. Result sample's missed rows use "build" ("I ended up carrying…"), a kind no longer dealt.
   Use the gap miss.
5. Translate explanation must show "지난번엔 이렇게 말했어요" with the learner's own pair; check the
   kit's `was/fixed` render matches the app (piece 01 renders used it; re-verify).

## Channels

- IG carousel, 8 items. Threads REPLY under 05: opens on "did any of it stick?", answer in one
  line (a test from your own week, nothing else), the one surprise (your mistake comes back in a
  sentence you haven't seen), "틀린 건 다음 주에 다시". ≤ 500 chars.
- Community: replace e16 (it states a monthly test and the build kind); founder approval.

## Facts that must stay true

- Built only from the learner's own week; an item with no source in their material is not dealt.
- Kinds dealt today: meaning, gap, translate, listen, speak, grammar, upgrade. NOT build (old
  papers only), NOT monthly.
- Misses return in the weekly paper (badge Again), last 4 papers, up to 5. No "월간 시험".
- No streak flame, no gauge, no confetti on the test.
- Scores are counts of right answers; "6 / 7" is sample data.
- Opens weekly at a time the learner sets (default Saturday 10:00); don't promise "every Saturday".

## Risks / copy traps

1. Don't sell it as a level test; it's a check of THIS week. Level lives in Progress.
2. The translate prompt and its answer must come from the real engine (run the app on the sample
   week, take its sentence), not invented; same for decoys.
3. "AI가 채점해요": wrong. Code grades; say "정답은 정해져 있어요" style or nothing.

## Success signal

- Saves; replies asking "시험이 어디 있어요?" = the door needs a better pointer.
- Product: `weekly_test_started` / `weekly_test_finished` per weekly active learner, before vs
  after (PostHog, read-only).
