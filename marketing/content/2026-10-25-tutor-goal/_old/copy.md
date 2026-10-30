# 튜터 모드 (목표 수업) — copy, 6 cards

Autopilot run for 1.2.4 (build 120), the tutor-mode REDESIGN. Series: **나와나로 할 수 있는 것**,
cat `talk`. This REPLACES the old tutor beat (`2026-10-13-tutor-mode`, e06) — refresh e06, do not
stack a second tutor episode (lead to confirm the id; see the series entry below).

The one message: **수다가 아니라 수업이에요. 오늘 말하고 싶은 걸 정하면 유창한 내가 작은 과제로
쪼개서, 제대로 말할 때까지 같이 연습해요.** Emotional core: **될 때까지.** The teacher is my own
cloned voice, never a stranger, never a scold. Every card traces to it.

Written in Korean first, then separately in English — not translated. The on-screen conversation
lines (`say()` / `user()` / `fix(...)` sample) are MATERIAL and stay English; every label and
description around them is 해요체. The fluent self's own quoted lines are 반말. Never "당신".
No em dashes anywhere. Numbers on chips/cards (level chip, any score) are illustrative kit sample
data — never a user result; the app does not grade you and does not hand you a level.

Length target (matching the approved sibling pieces): ko descriptions ~38–56 characters, en
~90–135 characters, 2 lines on the render. Titles 2 lines, ~3–6 characters a line (ko).

**For the designer (built ONLY from `nw-call` — no new screen, no settings sheet):**
- Eyebrow number → `NN / 06`.
- Every body card is `nw-call`; title inside = the lesson topic (kit sample), level chip B1/B2,
  Futureself pill lit, "Future self" label (the own-voice hook carried visually).
- The `call` goals chip row IS the TutorLessonStrip checklist: each chip = one challenge, an empty
  circle until nailed. `call.goals([...])` lays it (all empty circles), `call.tick(n)` turns
  challenge n's circle into a **green checkmark**, `call.fix({...})` shows the correction card.
  The checklist is visible from card 2 on.
- Correction card (card 3) is the key sticker: it carries "제대로 말할 때까지". Green-check tick
  (cards 4–5) is the payoff — keep the circle → check motion crisp.
- All on-screen sentences are kit sample data (neutral sample name, a wrong verb). Never a real
  user, result or stat; don't use the founder's name. Futureself mosaic clipped inside the pill only.
- Cards 2–5 as 8–12 s MP4 loops (checklist filling, fix card blooming, the tick landing); cover +
  outro as PNG. Cover must hold as a still in the grid.

---

## 01 — Cover: the call becomes a lesson with a goal
eyebrow (ko): 나와나로 할 수 있는 것 · 01 / 06
title (ko): 통화가\n수업이 돼요
desc (ko):  오늘 말하고 싶은 걸 정하면,\n유창한 내가 **될 때까지** 가르쳐줘요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): What you can do with nawana · 01 / 06
title (en): Your call\nbecomes a lesson
desc (en):  Pick what you want to say today,\nand it teaches you **until you nail it.**
footer (en): Swipe → · nawana.app

screen: `nw-call`, checklist already laid (3–4 empty-circle chips), one fluent-self `say()` bubble, Futureself pill lit, "Future self" label
material on screen (stays English): the fluent self's opening `say()` line
alt (ko): 통화 화면 위에 과제 서너 개가 빈 동그라미로 놓여 있고, 유창한 내가 수업을 열고 있어요. 내 목소리로 말하는 "미래의 나" 라벨과 켜진 픽셀 알약이 보여요.
alt (en): The call screen with three or four empty-circle challenges laid across the top and your fluent self opening the lesson. The "Future self" label and lit Futureself pill carry the own-voice hook.

## 02 — 목표를 정하면 과제가 돼요 (you pick, it splits)
eyebrow (ko): 나와나로 할 수 있는 것 · 02 / 06
title (ko): 목표를\n정하면 돼요
desc (ko):  말하고 싶은 걸 꺼내면, 유창한 내가\n**작은 과제 서너 개**로 쪼개줘요.

eyebrow (en): What you can do with nawana · 02 / 06
title (en): Just set\nthe goal
desc (en):  Say what you want to be able to say, and it splits it into **three or four challenges.**

screen: `nw-call`, `say()` asks what you want to say today ("What do you want to be able to say today?") → `goals([...])` populates the chip row, all empty circles
material on screen (stays English): the fluent self's topic question
motion: the checklist filling in, empty circles
sticker option: the 💡 topic button, from the bar
alt (ko): 유창한 내가 오늘 뭘 말하고 싶은지 물어요. 답을 주면 위쪽 체크리스트에 빈 동그라미 과제가 하나씩 떠요.
alt (en): Your fluent self asks what you want to say today; your answer fills the checklist above with empty-circle challenges, one by one.

## 03 — 될 때까지 (1): 틀려도 괜찮아요 (HERO sticker: fix card)
eyebrow (ko): 나와나로 할 수 있는 것 · 03 / 06
title (ko): 틀려도\n괜찮아요
desc (ko):  틀린 곳만 짚어서, 바른 문장을\n**제대로 말할 때까지** 같이 해요.

eyebrow (en): What you can do with nawana · 03 / 06
title (en): Getting it\nwrong is fine
desc (en):  It points at just the slip and shows the right line, **until you say it clean.**

screen: `nw-call`, `user()` half-wrong line → `fix({ text, note, fixes:[{was, now}] })` correction card; checklist chip 0 still an open circle
material on screen (stays English): the learner's half-wrong `user()` line and the fix card's right version
motion: the fix card blooming
alt (ko): 내가 반쯤 틀리게 말하면 교정 카드가 떠서 바른 문장을 보여줘요. 첫 과제 동그라미는 아직 빈 채예요. 제대로 말할 때까지요.
alt (en): After a half-wrong line, a correction card shows the right version. The first challenge's circle is still open until you say it clean.

## 04 — 될 때까지 (2): 맞게 말하면 초록 체크
eyebrow (ko): 나와나로 할 수 있는 것 · 04 / 06
title (ko): 맞으면\n초록 체크
desc (ko):  제대로 말하면 과제에 체크가 떠요.\n그래도 **한 번 더**, 익을 때까지요.

eyebrow (en): What you can do with nawana · 04 / 06
title (en): Say it right,\na green check
desc (en):  Nail it and the challenge ticks green. Then **once more**, until it sticks.

screen: `nw-call`, `user()` says it clean → `tick(0)` turns the first chip into a green checkmark; the fluent self asks for it once more before moving on
material on screen (stays English): the learner's clean `user()` line and the fluent self's "once more" `say()` line
motion: the first chip's circle → green check
alt (ko): 내가 제대로 말하면 첫 과제 동그라미가 초록 체크로 바뀌어요. 그래도 유창한 내가 한 번 더 해보자고 해요. 익을 때까지요.
alt (en): Say it clean and the first challenge's circle turns into a green check. Even then your fluent self asks for it once more, until it sticks.

## 05 — 하나씩 다 채우면, 끝은 내가 골라요
eyebrow (ko): 나와나로 할 수 있는 것 · 05 / 06
title (ko): 하나씩\n다 채워요
desc (ko):  과제를 다 채워도 통화는 안 끝나요.\n더 할지, 새 목표로 갈지 **내가 골라요.**
footer (ko): 튜터 모드는 꺼져 있어요 · 통화 설정에서 켜세요

eyebrow (en): What you can do with nawana · 05 / 06
title (en): One by one,\nall filled
desc (en):  All challenges done, the call doesn't end. More, a new goal, or stop, **your choice.**
footer (en): Tutor mode is off · turn it on in call settings

screen: `nw-call`, `tick(1)`, `tick(2)`… the checklist mostly/fully green, last chip = the "put-it-together" challenge
material on screen (stays English): the fluent self's "a bit more, or another topic?" `say()` line
motion: the checks landing one after another
alt (ko): 체크리스트가 하나씩 초록으로 채워지고, 마지막 과제는 배운 걸 한데 모아 말하는 거예요. 다 채워도 유창한 내가 더 할지 새 목표로 갈지 물어요. 끝내는 건 내 몫이에요.
alt (en): The checklist fills green one chip at a time, the last challenge putting it all together. Even when it's full, your fluent self asks whether to keep going or start a new goal. Ending the call stays yours.

## 06 — Outro (fixed)
eyebrow: none (06 / 06 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 "유창한 나에게 언어를 배우세요.", "첫 20분은 무료예요", nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

나와나 통화가 이제 수업이 돼요. 될 때까지요.

수다만으론 늘고 있는지 모르겠을 때, 튜터 모드를 켜보세요.
오늘 말하고 싶은 걸 정하면, 유창한 내가 작은 과제 서너 개로 쪼개줘요.
한 문장을 제대로 말할 때까지 같이 연습하고, 맞으면 초록 체크가 떠요.
과제를 다 채워도 통화는 안 끝나요. 더 할지, 새 목표로 갈지 내가 골라요.

새 목표로 가면 지금까지 한 통화는 복습 교재로 저장돼요.
하다 멈춘 수업은 21일 동안 이어서 할 수 있고요.
가르쳐주는 건 내 목소리 그대로인 미래의 나예요. 모르는 사람도, 혼내는 선생님도 아니고요.

튜터 모드는 꺼져 있어요. 통화 설정에서 켜세요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #튜터모드 #nawana

(≈ 430 chars)

## Instagram caption (en)

Your nawana call is a lesson now. Until you nail it.

When free chat leaves you wondering if you're actually improving, turn on tutor mode.
Pick what you want to say today, and your fluent self splits it into three or four small challenges.
You stay on one line until it comes out clean, and a green check lands when it does.
Finish them all and the call doesn't end. Keep going, start a new goal, or stop. That's yours.

Start a new goal and the talk so far saves as its own review book.
Stop mid-lesson and it waits 21 days for you to pick it back up.
The teacher is your own cloned voice, your fluent self. Never a stranger, never a scold.

Tutor mode is off until you turn it on. It's in call settings.

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #nawana

(≈ 830 chars)

## Threads (ko)

나와나 통화가 이제 수업이 돼요. 될 때까지요.

튜터 모드를 켜고 오늘 말하고 싶은 걸 정하면, 유창한 내가 작은 과제 서너 개로 쪼개줘요. 한 문장을 제대로 말할 때까지 같이 하고, 맞으면 초록 체크. 다 채워도 통화는 안 끝나고, 더 할지 새 목표로 갈지는 내가 골라요. 새 목표로 가면 지금까지 한 통화는 복습 교재로 저장되고, 멈춘 수업은 21일 동안 이어서 할 수 있어요. 가르쳐주는 건 내 목소리 그대로인 미래의 나고요.

통화 설정에서 켜세요. 첫 20분은 무료예요. nawana.app

(≈ 280 chars)

## Threads (en)

Your nawana call is a lesson now. Until you nail it.

Turn on tutor mode, pick what you want to say, and your fluent self breaks it into three or four challenges. You stay on one line until it comes out clean, then a green check lands. Finish them all and the call keeps going. More, a new goal, or stop, that's yours. Switch goals and the talk so far saves as a review book; stop mid-lesson and it waits 21 days. The teacher is your own cloned voice.

Turn it on in call settings. First 20 minutes free. nawana.app

(≈ 480 chars)

## Community series entry

cat `talk`. **Refresh e06** (the old tutor slot, between e05 통화가 교재로 and e07 watch run) with the
redesign — do NOT add a second tutor episode (brief). The old e06 said "the fluent self teaches on
every turn"; this one says the call becomes a lesson with a goal you repeat until clean. Editing
`series.json` changes the live site → founder approval.

ko: { title: "튜터 모드", tagline: "목표를 정하면 될 때까지 가르쳐줘요" }
en: { title: "Tutor mode", tagline: "Set a goal, and it teaches until you nail it" }

---

## Open questions (for the lead)

1. **Episode id.** Written to refresh **e06** (`cat: talk`), the existing tutor slot, with new
   title/tagline + the 1.2.4 slides. Confirm reuse (not a new id), since the app behaviour changed
   and the old e06 copy is now wrong.
2. **On-screen line stays English.** Card 2's hook is the topic question; the Korean title/desc
   frame it, but the actual `say()` bubble renders in English (kit sample, e.g. "What do you want to
   be able to say today?"). Confirm the kit can script `say()` → `goals([...])` → `fix(...)` →
   `tick(n)` on `nw-call` with the chrome in the reader's language and the dialogue in English.
3. **"제대로 말할 때까지" / "until you nail it".** Copy rests on: clean = per-turn correction found no
   mistake AND the line did the challenge (the app's call, not the tutor's), and the tutor asks for
   it "once more" on a clean line before moving on. Confirm this reads true against the 2026-10-24
   CLAUDE.md paragraph and no card implies the tutor grades you.
4. **CTA location.** Caption/Threads/card 05 say tutor mode is OFF by default and lives in call
   settings. Confirm the switch label is 튜터 모드 and the location/icon matches build 120 (the
   older piece used the graduation-cap icon; I left the icon out of this copy to be safe).
5. **"첫 20분은 무료예요" (BRAND fact).** Re-confirm `freeGrantSeconds` = 1200 and "first 20 minutes
   free, no trial" on the post date. No "무료 체험 / free trial" anywhere.
6. **Captions + Threads + the e06 series edit need approval before posting** (nawana never posts
   without the founder's OK). All within limits (IG en ≈ 830 chars, Threads en ≈ 480 / ko ≈ 280).
