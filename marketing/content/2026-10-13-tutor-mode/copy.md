# 튜터 모드 — copy (tutor mode, 6 cards)

Autopilot run for 1.1.9. Series: **나와나로 할 수 있는 것**, cat `talk`, episode **e06** (the open slot
beside e04 교정 / e05 통화가 교재로 — lead to confirm the id). The one message:
**통화에서 튜터 모드를 켜면, 유창한 내가 그냥 대화 말고 매 턴 수업을 해줘요. 바른 말을 내 목소리로 소리 내
들려주고, 그 말을 쓰게 질문을 던져요.** 감정의 핵심은 **내 목소리가 선생님이 된다.** Every card traces to
it. Each card was written in Korean first and then separately in English, not translated. The teaching
and the conversation lines on screen are MATERIAL and stay English (the kit's own `say()` / `user()`
sample); every label and description around them is 해요체. The fluent self's own quoted lines are 반말.
Never "당신". No em dashes anywhere.

KO toggle label is **튜터 모드** (the exact app switch) everywhere the reader turns it on. "수업" is used
only as the plain noun for what it does (a lesson). We never write "수업을 켜세요"; it is always
"튜터 모드를 켜면 / 켜세요".

Length target (matching the approved sibling pieces): ko descriptions ~40–58 characters, en ~90–140
characters, 2 lines on the render. Titles 2 lines, ~5–9 characters a line.

**For the designer (screens + beats per brief — all on the live `nw-call` screen, NO new tab/screen,
NO settings sheet, NO correction card):**
- Eyebrow number → `NN / 06` (01 / 06 … 06 / 06).
- The teaching rides INSIDE the fluent self's spoken `say()` bubble, in the learner's own cloned voice.
  Do NOT draw a `fix` correction card (✕ was / ✓ now), the `coach` pose, "이렇게 말해 보세요 / Try saying",
  "써 볼 단어 / Try using" or a "썼어요 ✓ / Used it" chip — those are the older Coach mode and must not
  appear in this piece.
- Cover (01): `nw-call`, fluent self mid-teaching `say()` line, Futureself pill lit, "Future self"
  label (the own-voice hook carried visually). Must hold as a still in the grid. Light motion only.
- Card 02: `nw-call`, `say()` opens a theme ("Let's start with introducing yourself. What's your
  name?") → `listen()`. Sets up that this is a lesson. PNG or short loop.
- Card 03 (HERO): 8–12 s MP4. `user()` says it half-wrong ("I go to hiking with my friends.") →
  `say()` teaches it back aloud in the learner's own voice ("We'd say: I go hiking with my friends.
  Where do you usually go?"). The teaching is the SPOKEN bubble, no card.
- Card 04: 8–12 s MP4. `user()` says something correct ("My name is Eunggyu.") → `say()` gives "Good."
  plus one step up, still in the spoken bubble ("Good. With friends, just: I'm Eunggyu. What do you
  do?").
- Card 05: `nw-call`, `say()` ends on the practice question, `user()` answers using the taught line,
  then the theme moves on ("Now let's talk about your work."). PNG. State the switch (footer).
- Outro (06): the fixed series outro — Futureself pill speaking (clipped, light), wordmark, one offer
  line, nawana.app. No plan prices.
- All on-screen sentences are kit sample data (a neutral sample name, a wrong verb) — never a real
  user, result or stat. Don't use the founder's name. Futureself mosaic clipped inside the pill only.

---

## 01 — Cover: turn on tutor mode, the call becomes a lesson
eyebrow (ko): 나와나로 할 수 있는 것 · 01 / 06
title (ko): 미래의 내가\n선생님이 돼요
desc (ko):  통화에서 **튜터 모드**를 켜면,\n그냥 대화가 아니라 수업이 돼요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): What you can do with nawana · 01 / 06
title (en): Your fluent self\nbecomes the teacher
desc (en):  Turn on **tutor mode** in a call,\nand it stops chatting and teaches.
footer (en): Swipe → · nawana.app

screen: `nw-call`, fluent self mid-teaching `say()` line, Futureself pill lit, "Future self" label
alt (ko): 통화 화면에서 유창한 내가 수업을 하고 있어요. 내 목소리로 말하는 "미래의 나" 라벨과 켜진 픽셀 알약이 보여요.
alt (en): The call screen with your fluent self teaching. The "Future self" label and the lit Futureself pill carry the own-voice hook.

## 02 — 미래의 내가 수업을 이끌어요 (it leads the lesson)
eyebrow (ko): 나와나로 할 수 있는 것 · 02 / 06
title (ko): 미래의 내가\n수업을 이끌어요
desc (ko):  주제를 꺼낼 필요 없어요.\n**한 번에 하나씩** 이끌어 가요.

eyebrow (en): What you can do with nawana · 02 / 06
title (en): Your fluent self\nleads the lesson
desc (en):  You don't bring a topic.\nIt leads **one theme at a time.**

screen: `nw-call`, `say()` opens a theme ("Let's start with introducing yourself. What's your name?") → `listen()`
material on screen (stays English): the fluent self's opening `say()` line, then the empty "Listening…" bubble
alt (ko): 유창한 내가 먼저 주제를 열고 질문을 던져요. 아래에 비어 있는 "Listening…" 말풍선이 떠서 이제 내 차례예요.
alt (en): Your fluent self opens a theme and asks the first question; an empty "Listening…" bubble shows it's your turn.

## 03 — 틀리면, 맞는 말을 내 목소리로 (HERO)
eyebrow (ko): 나와나로 할 수 있는 것 · 03 / 06
title (ko): 맞는 말을\n내 목소리로
desc (ko):  틀리게 말하면, 바른 문장을\n**내 목소리로** 소리 내 들려줘요.

eyebrow (en): What you can do with nawana · 03 / 06
title (en): The right line,\nin your own voice
desc (en):  Slip up, and it says the line back\nthe right way, **aloud in your voice.**

screen: `nw-call`, `user()` half-wrong line → `say()` teaches it back aloud in the learner's own voice (no card)
material on screen (stays English): the learner's half-wrong `user()` line and the fluent self's spoken `say()` teaching line
alt (ko): 내가 반쯤 틀리게 말하면, 유창한 내가 바른 문장을 그 자리에서 내 목소리로 소리 내 들려주고 다음 질문을 이어가요. 따로 교정 카드는 없어요.
alt (en): After a half-wrong line, your fluent self says the correct version aloud in your own voice and carries straight on with the next question. No separate card.

## 04 — 맞아도, 한 걸음 더 (right isn't the end)
eyebrow (ko): 나와나로 할 수 있는 것 · 04 / 06
title (ko): 맞아도\n한 걸음 더
desc (ko):  잘 말했으면 "Good.",\n그다음 **더 나은 한마디**를 얹어줘요.

eyebrow (en): What you can do with nawana · 04 / 06
title (en): Right? Still\none step up
desc (en):  Nailed it? A quick "Good.",\nthen **a better way** on top.

screen: `nw-call`, `user()` correct line → `say()` gives "Good." + one step up, still in the spoken bubble
material on screen (stays English): the learner's correct `user()` line and the fluent self's "Good." + step-up `say()` line
alt (ko): 내가 맞게 말해도 끝이 아니에요. 유창한 내가 "Good." 하고, 더 쓸모 있는 한마디를 내 목소리로 얹어 들려줘요.
alt (en): Getting it right isn't the end. Your fluent self says "Good." then adds a more useful way to put it, aloud in your own voice.

## 05 — 바로 쓰게 묻고, 넘어가요 (a question to reuse it, pressure-free)
eyebrow (ko): 나와나로 할 수 있는 것 · 05 / 06
title (ko): 바로 쓰게\n물어봐요
desc (ko):  방금 배운 말로 답하게 묻고 넘어가요.\n점수 없는 **연습 통화**라 편해요.
footer (ko): 튜터 모드는 꺼져 있어요 · 통화 설정에서 켜세요

eyebrow (en): What you can do with nawana · 05 / 06
title (en): It asks you\nto use it
desc (en):  It asks so your next answer uses it, then moves on.\nA **practice call**, nothing to lose.
footer (en): Tutor mode is off · turn it on in call settings

screen: `nw-call`, `say()` ends on the practice question, `user()` answers using the taught line, theme moves on
material on screen (stays English): the fluent self's practice question, the learner's answer, and the next-theme `say()` line
alt (ko): 유창한 내가 방금 배운 말을 쓰게 질문하고, 내가 그 말로 답하면 다음 주제로 넘어가요. 점수 안 매기는 연습 통화예요.
alt (en): Your fluent self asks a question built to reuse what it taught; you answer with it, and the lesson moves to the next theme. A practice call, nothing graded.

## 06 — Outro
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

통화에서 튜터 모드를 켜면, 유창한 내가 그냥 수다 말고 진짜 수업을 해줘요.

내가 무슨 말을 하든, 매 턴 가르쳐요.
틀리면 바른 문장을, 뻣뻣하면 더 자연스러운 말을, 잘 말했으면 "Good." 다음 한 걸음 더를.
전부 내 목소리로 소리 내 들려주고, 방금 그 말로 답하게 질문을 던져요.

점수 안 매기는 연습 통화라 더듬거려도 괜찮아요.

튜터 모드는 통화 설정(졸업 모자 아이콘)에 있어요. 켜기 전엔 꺼져 있으니, 한 번 켜보세요.

내 목소리가 선생님이 되는 거예요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #nawana

(≈ 300 chars)

## Instagram caption (en)

Turn on tutor mode in a call, and your fluent self stops just chatting. It runs a real lesson.

Whatever you say, it teaches, every turn.
Slip up and it gives the right line. Sound stiff and it gives the natural one. Say it well and it's "Good." then one step up.
All of it spoken aloud, in your own voice, and then a question you answer by using what it just taught.

It's a practice call, not graded, so stumbling is fine.

Tutor mode lives in call settings, under the graduation cap. It's off until you turn it on, so give it a try.

Your own voice, becoming your teacher.

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #nawana

(≈ 650 chars)

## Threads (ko)

통화에서 튜터 모드를 켜면, 유창한 내가 그냥 수다 말고 수업을 해줘요.

내가 무슨 말을 하든 매 턴 가르쳐요. 틀리면 바른 문장을, 잘 말했으면 한 걸음 더를, 전부 내 목소리로 소리 내 들려주고 그 말을 쓰게 질문을 던져요. 점수 없는 연습 통화라 편하고요.

졸업 모자 아이콘, 통화 설정에 있어요. 켜기 전엔 꺼져 있으니 한 번 켜보세요.

내 목소리가 선생님이 되는 거예요.

첫 20분은 무료예요. nawana.app

(≈ 190 chars)

## Threads (en)

Turn on tutor mode in a call and your fluent self stops just chatting. It teaches.

Every turn: slip up, hear the right line; say it well, hear one step up. All of it aloud, in your own voice, then a question you answer by using it. It's a practice call, so stumbling costs nothing.

It's in call settings, under the graduation cap. Off until you turn it on.

Your own voice, as your teacher.

Your first 20 minutes are free. nawana.app

(≈ 400 chars)

## Community series entry

cat: `talk`. Episode **e06** — the open slot between e05 (통화가 교재로) and e07 (watch run). Sits right
after e04 (교정): e04 says mistakes get fixed inside a normal call; e06 says the whole call becomes a
lesson the fluent self leads. Adding it to `series.json` changes the live site → founder approval.

ko: { title: "튜터 모드", tagline: "내 목소리가 선생님이 돼요" }
en: { title: "Tutor mode", tagline: "Your own voice becomes the teacher" }

---

## Open questions (for the lead)

1. **Episode id.** Written as e06 (`cat: talk`), the open slot after e05. Confirm, or remap if board
   order should differ. The talk run is e02…e05 + this.
2. **Kit beats.** Cards 03/04 need the `say()`→`user()`→`say()` teaching loop with the teaching carried
   in the spoken `say()` bubble (own voice), no `fix` card and no `coach` pose. Confirm the kit can
   script this on `nw-call` and that the on-screen teaching lines render in English (material) with the
   ko/en slide chrome in the reader's language.
3. **Toggle location copy.** Caption/Threads/card 05 say the switch is in call settings under the
   graduation cap icon and is OFF until turned on. Confirm the icon + location wording matches the ship
   build (graduationcap, labeled 튜터 모드).
4. **"Practice call" accuracy (brief risk).** Copy says "점수 안 매기는 연습 통화 / practice call, not
   graded" and never a flat "안 쳐줘요 / it doesn't count". Minutes, streak and corrections→cards still
   count. Confirm the wording holds and we never imply nothing counts.
5. **"첫 20분은 무료예요" (BRAND fact).** Re-confirm `freeGrantSeconds` = 1200 and "first 20 minutes free,
   no trial" on the post date. No "무료 체험 / free trial" anywhere.
6. **Captions + Threads + the e06 series entry need approval** before posting (nawana never posts
   without the founder's OK). All well under limits (IG en ≈ 650, Threads en ≈ 400).
