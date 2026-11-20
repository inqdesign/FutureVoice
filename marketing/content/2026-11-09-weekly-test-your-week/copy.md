# 내 한 주로 만든 시험 · copy (6 cards)

Piece: 2026-11-09-weekly-test-your-week (1.3.2 / build 136). The redesign (2026-11-08):
the weekly test is built ONLY from that week's own material — words the calls taught,
phrases the fluent self offered, corrected sentences, lines worth hearing again. A right
answer counts as "known" everywhere (retires from review cards AND books). "제 답도 맞아요"
appeals a wrong mark.

Korean written as Korean, English written as English; same meaning, never a gloss.
해요체, no 당신. The fluent self, if quoted, speaks 반말 (here it only appears as the
English material lines on screen). Positive first. No em dash anywhere in posted text.

Eyebrow series label: **주간 테스트** (ko) / **Weekly test** (en), n/total on the right.
This is the UPDATE, not the e16 catalogue re-run — see Community note.

**For the designer (hard constraints from brief):**
- **No streak flame, no score gauge.** The kit `nw-weeklytest` enforces this; never add
  or imply either on any card.
- **A thin week doesn't open the test.** Card 03's note says it as a feature (네 한 주가
  기준), never "unlocked after N items".
- **Known-everywhere (card 04) and the appeal (card 05) are TEXT ONLY.** There is no
  dedicated screen for either. Use the test/result captures beside the copy. Do NOT draw a
  standalone "이의제기 / appeal" button screen — the app has none.
- **Item kinds are the six real ones:** meaning · gap · translate · grammar · listen ·
  speak. Don't invent a seventh.
- Every word/score/count on screen is illustrative kit sample data, never a user result.
- App labels stay the app's own (kit `weeklytest.js` ko): 주간 테스트 · 빈칸 채우기 ·
  내 실수에서 나온 말 · 지난번엔 이렇게 말했어요 · 잘한 한 주예요 · 틀린 것 · 제 답도 맞아요.
- Items (material, English on both versions — designer takes the kit's real sample):
  - gap (cards 01, 02): e.g. "You clearly _____ and prioritized what mattered." →
    took the initiative. Must be the engine's real output.
  - grammar (card 03 main): a slip from the learner's own line, rebuilt right from tiles.
  - listen (card 03 sticker): a fluent-self line, heard with its text hidden.
  - result (cards 04, 05): a score (e.g. 6 / 7), 잘한 한 주예요, one missed row.
- Cards 02–05 as 8–12 s MP4 loops; cover + outro PNG; the cover must hold as a still.

---

## 01 · Cover: a test made from your week
eyebrow (ko): 주간 테스트 · 01 / 06
title (ko): 내 한 주로\n만든 시험
desc (ko):  그 주에 **내가 공부한 것**으로만 시험을 만들어요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): Weekly test · 01 / 06
title (en): A test made\nfrom your week
desc (en):  Built only from **what you studied** that week.
footer (en): Swipe → · nawana.app

screen: `nw-weeklytest` on a clean `weekly-test-gap` item (one question read clearly). Phone moves in, text fades.
alt (ko): 주간 테스트의 빈칸 문항 한 개가 깔끔하게 보이는 표지예요. 위에는 '내 한 주로 만든 시험'이 있어요.
alt (en): Cover: one clean fill-in-the-blank question from the weekly test, under the title "A test made from your week".

## 02 · What this week's calls taught
eyebrow (ko): 주간 테스트 · 02 / 06
title (ko): 통화가 가르친\n단어와 표현
desc (ko):  빈칸에 들어갈 말은 **유창한 내가 통화에서 쓴 표현**이에요.

eyebrow (en): Weekly test · 02 / 06
title (en): Words your\ncalls taught
desc (en):  The blank wants **a phrase the fluent you used** on a call.

screen: `weekly-test-gap` — the gap item, the phrase tapped into the blank, marked right
sticker (optional): the small gap question card beside the phone (allowed by the brief)
alt (ko): 'You clearly _____ and prioritized what mattered.' 빈칸에 'took the initiative'를 골라 정답이 돼요.
alt (en): In "You clearly _____ and prioritized what mattered.", "took the initiative" is picked and marked right.

## 03 · Corrected sentences, lines worth hearing again
eyebrow (ko): 주간 테스트 · 03 / 06
title (ko): 한 주가\n통째로 들어와요
desc (ko):  교정됐던 문장도, 다시 들어 볼 만했던 줄도 **그대로** 문제가 돼요.
note (ko): 한 주가 얇으면 시험은 열리지 않아요. 내 한 주가 기준이니까요.

eyebrow (en): Weekly test · 03 / 06
title (en): Your whole\nweek, at once
desc (en):  The sentences you fixed and the lines worth hearing again, **all of it**.
note (en): A thin week simply doesn't open the test. Your own week is the measure.

screen: `weekly-test-grammar` as the main (a past-tense slip rebuilt right from word tiles). Designer chose grammar-only, no listen sticker, so the alt describes just that.
alt (ko): 내가 자꾸 틀리던 과거 시제를 처음 보는 문장으로, 타일을 순서대로 눌러 맞게 다시 만들어요.
alt (en): A past-tense slip you keep making, rebuilt right in a new sentence by tapping the word tiles in order.

## 04 · Get it right, known everywhere
eyebrow (ko): 주간 테스트 · 04 / 06
title (ko): 맞히면\n어디서나 아는 말
desc (ko):  맞힌 단어와 문장은 **복습 카드와 교재에서도** 아는 것으로 바뀌어요.
note (ko): 시험, 카드, 교재가 하나로 이어져요.

eyebrow (en): Weekly test · 04 / 06
title (en): Get it right,\nknown everywhere
desc (en):  A right answer turns known in **your review cards and books** too.
note (en): The test, your cards and your books move together.

screen: `weekly-test-result` — the result page, a score (sample), 잘한 한 주예요, a missed row
alt (ko): 결과 화면에 점수와 '잘한 한 주예요', 틀린 문제 한 줄이 보여요. 숫자는 예시예요.
alt (en): The result page with a sample score, "A good week", and one missed row listed below.

## 05 · "My answer is right too" (TEXT ONLY — never draw an appeal screen)
eyebrow (ko): 주간 테스트 · 05 / 06
title (ko): "제 답도\n맞아요"
desc (ko):  틀렸다고 나와도 내 답이 맞으면, **한 번 눌러** 맞은 걸로 바로잡아요.

eyebrow (en): Weekly test · 05 / 06
title (en): "My answer\nis right too"
desc (en):  Marked wrong but you were right? **One tap** counts it correct.

screen: a `weekly-test-translate` item marked WRONG ('이번엔 아니에요' / 'Not this time') — the exact moment the appeal lives. The appeal is told in COPY only; no dedicated screen, no button mockup.
alt (ko): 번역 문항('어제 면접관이 다시 전화했어')을 타일로 조립했는데 '이번엔 아니에요'로 틀리게 나와요. 이런 순간 '제 답도 맞아요'로 바로잡는다는 걸 글로 보여줘요.
alt (en): A translate item ("어제 면접관이 다시 전화했어") built from tiles and marked "Not this time". Copy explains this is where "My answer is right too" sets it straight.

## 06 · Outro (fixed)
eyebrow: none (06 / 06 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 '유창한 나에게 언어를 배우세요.', '첫 20분은 무료예요', nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

시험이라고 하면 지겨운 문제집부터 떠오르죠.
나와나 주간 테스트는 내 지난 한 주로만 만들어요.

그 주 통화가 가르친 단어, 유창한 내가 쓴 표현이 문제로 나와요.
교정됐던 문장, 다시 들어 볼 만했던 줄까지 그대로요.
남이 만든 문제집에서 가져온 문제는 하나도 없어요.
맞힌 단어와 문장은 복습 카드와 교재에서도 아는 것으로 바뀌고요.
틀렸다고 나와도 내 답이 맞으면, "제 답도 맞아요"로 바로잡아요.

첫 20분은 무료예요 · 프로필 링크

#영어공부 #영어회화 #스피킹 #복습 #nawana

(≈ 290 chars)

## Instagram caption (en)

"Test" makes you picture a dull workbook.
nawana's weekly test is built only from your own past week.

The words your calls taught and the phrases the fluent you used become the questions.
The sentences you fixed, the lines worth hearing again, all of it.
Nothing pulled from a generic question bank.
Get one right and it turns known in your review cards and your books too.
Marked wrong but you were right? Tap "My answer is right too" and it counts.

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #englishgrammar #languagelearning #nawana

(≈ 560 chars)

## Threads (ko)

통화하고 복습 카드도 넘기며 한 주를 보냈는데, 정작 시험은 남의 문제집에서 나오면 좀 허무하잖아요.

나와나 주간 테스트는 그 주에 내가 공부한 것으로만 만들어요. 통화가 가르친 단어, 유창한 내가 쓴 표현, 교정됐던 문장, 다시 들어 볼 만했던 줄까지요. 한 주가 얇으면 시험은 아예 열리지 않아요.

맞힌 건 복습 카드와 교재에서도 아는 것으로 바뀌고, 틀렸다고 나와도 내 답이 맞으면 "제 답도 맞아요"로 바로잡아요.

첫 20분은 무료예요. nawana.app

(≈ 280 chars)

## Threads (en)

You study all week, then the test pulls questions from someone else's workbook. Deflating.

nawana's weekly test is built only from what you studied that week: the words your calls taught, the phrases the fluent you used, the sentences you fixed, the lines worth hearing again. A thin week doesn't open it.

Get one right and it's known in your cards and books too. Marked wrong but you were right? Tap "My answer is right too" and it counts.

Your first 20 minutes are free. nawana.app

(≈ 487 chars)

## Community (news draft, NOT a series entry)

Per brief: do NOT add a feature-series entry. e16 ("주간 시험 / Weekly test") already
covers the feature; this piece is the update. Publisher drafts a short NEWS post
(`community_news`), founder approves before publish. e16's existing tagline
("일주일 동안 배운 것만으로 만든 시험지" / "A test made only from what you learned this week")
still reads true, so leave it.

title (ko): 주간 테스트가 바뀌었어요
title (en): The weekly test just changed

body (ko):
주간 테스트가 그 주에 내가 공부한 것으로만 만들어져요. 통화가 가르친 단어, 유창한 내가 쓴
표현, 교정됐던 문장, 다시 들어 볼 만했던 줄이 그대로 문제가 돼요. 남의 문제집에서 가져온
문제는 없어요. 맞힌 단어와 문장은 복습 카드와 교재에서도 아는 것으로 바뀌고, 틀렸다고 나와도
내 답이 맞으면 "제 답도 맞아요"로 바로잡으면 돼요.

body (en):
The weekly test is now built only from what you studied that week: the words your calls
taught, the phrases the fluent you used, the sentences you fixed, the lines worth hearing
again. Nothing from a generic question bank. Get an answer right and it turns known in your
review cards and books too, and if you were marked wrong but you were right, "My answer is
right too" sets it straight.

---

## Open questions (for the lead)

1. **Gap / grammar / result sample data** (cards 01–05) must be the kit's real engine
   output (prompt, answer, decoys, score). My copy doesn't quote specific numbers, so it
   survives a different sample; the alt text on 02 quotes "took the initiative" — update it
   if the kit's gap item differs.
2. **Appeal button label.** Copy quotes "제 답도 맞아요" / "My answer is right too" from the
   brief. Confirm these are the kit's exact strings before render.
3. **Eyebrow label.** I used the feature's own name "주간 테스트 / Weekly test" (not the
   "나와나로 할 수 있는 것" catalogue lane), since this is an update, not a catalogue card.
   Say if the lead wants it folded into a lane.
4. **Community is a NEWS draft, not a series entry** (brief's instruction overrides the
   default "Community series" output). Flagging so the reviewer doesn't expect a series JSON
   change.
5. **Card 04 title (en)** "known everywhere" runs ~16 chars on line 2; trim to taste in the
   pixel layout if it crowds.
6. **Approval.** Captions, Threads and the news draft need the founder's OK before posting
   (autopilot still routes through the veto window).
