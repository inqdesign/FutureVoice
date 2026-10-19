# 내 한 주로만 만든 시험 · copy (series 06, 8 cards)

Written 2026-10-13 from `brief.md`. Same story: the interview week. Korean written as Korean,
English written as English. 해요체, no 당신, no em dash anywhere in this file. Nothing here says
monthly test, build, flame, gauge, level test, or "AI가 채점해요". The test opens at the time the
learner set (no "매주 토요일").

Eyebrow on every card: `nawana · NN / 08`.

**Korean clarity pass (2026-10-14).** Korean only; English unchanged. "내 한 주로만 만든" (needs
decoding) became "이번 주에 공부한 걸로만". Re-render ONLY these ko cards: **01** (desc line 1,
chips 04 and 05), **02** (title, desc), **04** (title, desc), **05** (desc), **06** (title).
03, 07, 08 unchanged. Captions, Threads and the community tagline rewritten.

**English clarity pass (2026-10-14).** English only; Korean untouched. "paper" (British test
sheet) became "test". Re-render ONLY these en cards: **01** (desc, chips 02, 04, 05), **02**
(title, desc), **03** (desc), **04** (title, desc), **05** (title, desc), **06** (title, desc),
**07** (desc). 08 unchanged. IG caption (en) rewritten with no sound line (silent export); Threads
(en) added as a reply in the English thread.

## For the designer

- **Card count 8.** `nawana · 01 / 08` … `08 / 08`.
- **App labels stay the app's own** (kit `weeklytest.js` ko): 주간 테스트 · 어떤 단어의 뜻일까요? ·
  빈칸 채우기 · 영어로 말하기 · 듣고 그대로 조립하기 · 함정 단어 · 내 실수에서 나온 말 · 지난번엔
  이렇게 말했어요 · 잘한 한 주예요 · 틀린 것 · 이것들은 복습으로 돌아가서 지금 바로 나와요.
- **Items (material, English on both versions; kit gap 2):**
  - 03 meaning: gloss of "perspective", four nouns (same-class decoys)
  - 04 gap: "You clearly _____ and prioritized what mattered." → took the initiative
  - 05 translate: prompt "어제 면접관이 다시 전화했어." → "The interviewer called me again yesterday."
    decoy "call" left in the tray; after: 과거 시제 + 지난번엔 이렇게 말했어요 · it go → it went.
    Prompt, answer and decoys must be the engine's real output (brief Risk 2).
  - 06 listen: "You clearly took the initiative and prioritized what mattered." (Audio A, reuse
    from the shadowing piece), text hidden, tiles laid in order.
- **07 result:** 6 / 7, 잘한 한 주예요, one missed row (the gap item, not build: kit gap 4), the
  footer line, then next week's paper with the same item and the "Again" badge (kit gap 1).
- No flame, no gauge, no confetti. UI answer sounds only if the founder says yes.

---

## 01 · Cover: problem, then the answer
eyebrow (ko): nawana · 01 / 08
title (ko): 공부는 했는데\n뭐가 남았을까요
desc (ko):  **이번 주에 공부한 걸로만 시험을 봐요.**\n이번 주 통화의 단어와 표현, 내 실수까지 나와요.
chips (ko):
  02 매주 한 번, 내 시험지
  03 이번 주 단어
  04 유창한 내가 쓴 표현
  05 틀린 문법은 새 문장으로
  06 듣고 맞추기
  07 틀린 건 다시
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · 01 / 08
title (en): You studied.\nDid it stick?
desc (en):  **A test made only from what you studied.**\nThis week's words and phrases, plus your own mistakes.
chips (en):
  02 Your own test, once a week
  03 This week's words
  04 Phrases the fluent you used
  05 Mistakes, in new sentences
  06 Listen and rebuild
  07 Misses come back
footer (en): Swipe → · nawana.app

screen: no phone. `nw-futureself` (speaking) in its circle + chip list
alt (ko): ‘공부는 했는데 뭐가 남았을까요’ 제목 아래 ‘이번 주에 공부한 걸로만 시험을 봐요’가 있고, 미래의 나 모자이크가 말하는 동안 02~07장 목차가 하나씩 나타나는 표지예요.
alt (en): Cover: "You studied. Did it stick?" over "A test made only from what you studied." The fluent-self mosaic speaks while the contents for cards 02 to 07 appear one by one.

## 02 · Once a week, my own paper
eyebrow (ko): nawana · 02 / 08
title (ko): 매주 한 번,\n나만의 시험지
desc (ko):  정해 둔 요일, 시간이 되면 **이번 주 공부로만 만든** 시험지가 열려요. 복습 탭 위쪽의 얼굴을 누르면 돼요.

eyebrow (en): nawana · 02 / 08
title (en): Once a week,\na test of your own
desc (en):  At the day and time you set, a test **built only from your week** opens. Tap the face at the top of Review.

screen: `nw-book` Review header, host face with its dot pressed → `nw-weeklytest` opens on 1/7, host blinks
alt (ko): 복습 탭 위쪽에 점이 붙은 얼굴을 누르자 주간 테스트가 열리고, 두 눈만 있는 진행자가 눈을 깜빡여요.
alt (en): The face with a dot at the top of the Review tab is tapped; the weekly test opens and its host, two pixel eyes, blinks.

## 03 · Words from this week's calls (silent)
eyebrow (ko): nawana · 03 / 08
title (ko): 이번 주 통화에\n나온 단어
desc (ko):  뜻을 보고 맞는 단어를 골라요. **이번 주 통화 교재**에서 아직 못 익힌 단어부터 나와요.

eyebrow (en): nawana · 03 / 08
title (en): Words from\nthis week's calls
desc (en):  See a meaning, pick the word. Words from **this week's calls** you haven't learned yet come first.

screen: meaning item, gloss of "perspective", four nouns → tap → right, host happy
alt (ko): 뜻풀이를 보고 네 단어 중 ‘perspective’를 고르자 정답이 표시되고 진행자의 눈이 웃어요.
alt (en): From a definition, "perspective" is picked out of four words; it's marked right and the host's eyes light up.

## 04 · A phrase the fluent me used, in the blank (silent)
eyebrow (ko): nawana · 04 / 08
title (ko): 빈칸에 들어갈\n표현을 골라요
desc (ko):  통화에서 유창한 내가 했던 문장이 **빈칸**과 함께 나와요. 거기 쓰였던 표현을 맞혀요.

eyebrow (en): nawana · 04 / 08
title (en): Pick the phrase\nfor the blank
desc (en):  A line the fluent you said on a call, with **a blank** where a phrase was. Pick the one it used.

screen: gap item "You clearly _____ and prioritized what mattered." → took the initiative → right
alt (ko): ‘You clearly _____ and prioritized what mattered.’ 빈칸에 ‘took the initiative’를 골라 정답이 돼요.
alt (en): In "You clearly _____ and prioritized what mattered.", "took the initiative" is picked and marked right.

## 05 · My grammar slip, in a new sentence
eyebrow (ko): nawana · 05 / 08
title (ko): 틀린 문법은\n새 문장으로
desc (ko):  내가 틀렸던 문법을 **처음 보는 문장**으로 다시 물어봐요. 함정 단어도 내가 틀렸던 말로 만들어요.

eyebrow (en): nawana · 05 / 08
title (en): Grammar you missed,\nin a new sentence
desc (en):  The grammar you got wrong comes back **in a sentence you haven't seen**, with trap words from your own mistakes.

screen: translate item, Korean prompt → tiles laid, decoy "call" left in the tray → right → 과거 시제 + 지난번엔 이렇게 말했어요 · it go → it went
alt (ko): ‘어제 면접관이 다시 전화했어’를 영어 단어 카드로 맞추고, 함정 단어 ‘call’은 남겨 둬요. 정답 뒤에 과거 시제 설명과 지난번에 ‘it go’라고 했던 말이 ‘it went’로 고쳐져 나와요.
alt (en): A Korean sentence meaning "The interviewer called me again yesterday" is built from English word tiles, leaving the trap word "call" behind. After the answer, a past-tense note shows the learner's old "it go" fixed to "it went".

## 06 · Listen, then rebuild it (Audio A)
eyebrow (ko): nawana · 06 / 08
title (ko): 듣고\n순서대로 맞춰요
desc (ko):  이번 주에 유창한 내가 한 말을 **글자 없이 듣고**, 단어 카드를 순서대로 놓아요.
hint (ko): 소리 켜고 들어 보세요

eyebrow (en): nawana · 06 / 08
title (en): Listen,\nthen put it in order
desc (en):  Hear a line the fluent you said this week **with no text on screen**, then put its words back in order.
hint (en): Turn the sound on

screen: listen item, play pressed, tiles laid in order
sound: A (reuse, shadowing piece)
alt (ko): 재생을 누르면 유창한 내가 한 문장이 글자 없이 들리고, 그 단어 카드를 순서대로 눌러 문장을 맞춰요.
alt (en): Play is tapped and a line from the fluent you is heard with no text; its word tiles are tapped back into order.

## 07 · What I missed comes back
eyebrow (ko): nawana · 07 / 08
title (ko): 틀린 건\n다시 나와요
desc (ko):  틀린 문제는 **바로 복습으로** 돌아가요. 다음 주 시험지에도 한 번 더 나와요.

eyebrow (en): nawana · 07 / 08
title (en): Missed it?\nIt comes back.
desc (en):  What you miss goes **straight back into review** and shows up again on next week's test.

screen: result 6 / 7 잘한 한 주예요, missed row (gap), footer line → next week's paper, same item with the Again badge
alt (ko): 결과 화면에 7문제 중 6개 정답과 ‘잘한 한 주예요’가 나오고, 틀린 빈칸 문제가 아래에 있어요. 다음 주 시험지에 그 문제가 다시 나와요.
alt (en): The result reads 6 of 7 with "A good week", the missed blank question listed below; next week's paper shows that question again.

## 08 · Outro (unchanged from piece 01)
eyebrow: none (08 / 08 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app
tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app
screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 ‘유창한 나에게 언어를 배우세요.’와 ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

공부는 했는데, 뭐가 남았는지 모르겠을 때 있죠.
그래서 일주일에 한 번, 이번 주에 공부한 걸로만 시험을 봐요.

이번 주 통화 교재의 단어, 유창한 내가 쓴 표현이 문제로 나와요.
틀렸던 문법은 처음 보는 문장으로 다시 묻고, 함정 단어도 내가 틀렸던 말로 만들어요.
유창한 내가 한 말을 글자 없이 듣고 순서대로 맞추기도 해요. 6번째 장은 소리 켜고 들어 보세요.
틀린 건 바로 복습으로 돌아가고, 다음 주 시험지에 다시 나와요.

첫 20분은 무료예요 · 프로필 링크

#영어공부 #영어회화 #스피킹 #복습 #nawana

## Instagram caption (en)

You studied all week. Did any of it stick?
Once a week, take a test made only from what you studied that week.

Words from this week's calls and phrases the fluent you used become the questions.
Grammar you got wrong comes back in a sentence you haven't seen, with trap words made from your own mistakes.
You also hear a line from the fluent you with no text, and put its words back in order.
Anything you miss goes straight back into review and shows up again on next week's test.

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #englishgrammar #languagelearning #nawana

## Threads (ko) · a reply under 05 (words)

일주일 내내 통화하고 단어도 넘겼는데, 그래서 뭐가 남았는지는 잘 모르겠죠.

그래서 일주일에 한 번, 이번 주에 공부한 걸로만 시험을 봐요. 이번 주 통화 교재의 단어, 유창한 내가 쓴 표현이 문제로 나와요. 남이 만든 문제집에서 가져온 문제는 없어요.

틀린 문법은 조금 다르게 나와요. 면접 통화에서 "it go"라고 했던 걸, 이번엔 처음 보는 문장으로 다시 물어봐요. 함정 단어도 내가 틀렸던 말로 만들고요.

틀린 건 바로 복습으로 돌아가고, 다음 주 시험지에 다시 나와요.

(≈ 290 chars, no hashtags, first 7 items)

## Threads (en) · a reply under 05 (words) in the English thread

You've talked and flipped cards all week, but what actually stuck?

Once a week, you take a test made only from what you studied. Words from your calls and phrases the fluent you used become the questions, nothing from a generic workbook.

Grammar works a little differently. You said "it go" on the interview call, so it asks again in a sentence you haven't seen, with trap words built from your mistake.

Anything you miss goes straight back into review and shows up on next week's test.

(≈ 490 chars, no hashtags, no sound line, first 7 items)

## Community series entry

Recommendation: REPLACE e16 (it states a monthly test and the build kind); founder approval.
cat: practice
ko: { title: "주간 테스트", tagline: "이번 주에 공부한 걸로만 만든 시험이에요" }
en: { title: "Weekly test", tagline: "A test made only from your week" }

---

## Open questions (for the lead)

1. **Card 05 sample** must be real engine output (prompt, answer, decoys); my copy doesn't quote
   them, so it survives a different sentence. The alt text does quote them: update it to match.
2. **"Again" badge ko label** isn't in the kit; designer should take the app's catalog value.
3. **Community title** "주간 테스트" (the app's name) replaces e16's "주간 시험".
4. **en result headline** in card 07's alt is "A good week": check the kit's en string.
