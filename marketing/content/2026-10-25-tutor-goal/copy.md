# 튜터 모드 (v2): 미래의 내가 선생님이 돼요 · copy, 6 cards

v2, the founder's rework (2026-10-26). Series: **나와나로 할 수 있는 것**, cat `talk`. Refreshes
the tutor slot **e06**; no new episode.

The one message: **미래의 내가 대화 상대에서 선생님이 돼요.** 배우고 싶은 말을 알려주면 과제 서너 개로
목표를 세우고, 과제마다 이렇게 말하면 된다고 예시를 들려준 뒤 직접 말해 보게 해요. Order on the
cards: role change → goal → guidance → you practise → checked off. Entry-level first (founder
approved for this feature); the higher-level beat is one line on card 05.

Korean written first as Korean, English written separately as English. On-screen conversation
lines (`say()` / `user()` / the fix card's line) are MATERIAL and stay English on both versions.
The checklist rows and the lesson title are written by the app in the NATIVE language
(`TutorPlanner`: "title" and "goal" in the native language), so they are Korean on the ko
version and English on the en version. Fluent-self lines are casual. No em dashes anywhere.

Length target (same as siblings): ko desc ~38–56 chars on 2 lines, en ~90–135 chars; titles 2
lines.

**For the designer (built only on `nw-call`, no new screen):**
- Eyebrow number → `NN / 06`.
- The checklist is tutor mode's own vertical lesson strip pinned under the nav bar
  (`call.tutor({ title, rows })`, matched against `marketing/captures/call-tutor*.png`): lesson
  title ko **자기소개하기** / en **Introducing yourself** with `n/4`, four numbered rows (the current
  one highlighted), ticked by `tutorTick(n)` (green check + strikethrough), finished by
  `tutorDone()` (green seal, "All done. You can say it now."). The 💡 topic button sits right of
  the pill. The nav keeps the call's own title (대화하기 / Let's talk). The goals chip row is NOT
  used (it is a different feature). Rows (as in the captures):
  - ko: `이름이랑 어디서 왔는지 말하기` · `하는 일 말하기` · `좋아하는 것 말하기` · `한 번에 다 말하기`
  - en: `Say your name and where you're from` · `Say what you do` · `Say what you like doing` · `Say it all in one go`
- Sample name **Mina** only. Numbers/levels on screen are kit sample data.
- Cards 02–05 as 8–12 s MP4 loops; cover + outro PNG; the cover must hold as a still.

---

## 01 · Cover: the role change
eyebrow (ko): 나와나로 할 수 있는 것 · 01 / 06
title (ko): 미래의 내가\n선생님이 돼요
desc (ko):  대화 상대에서 선생님으로.\n목표를 세우고 **하나씩** 가르쳐줘요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): What you can do with nawana · 01 / 06
title (en): Your future self\nbecomes your tutor
desc (en):  Not just someone to talk to anymore.\nIt sets a goal and teaches you **step by step.**
footer (en): Swipe → · nawana.app

screen: `nw-call` in tutor mode, the lesson strip 자기소개하기 / Introducing yourself laid (0/4, row 1 current). The opener and "I want to introduce myself." already said above; the last bubble is the first challenge's guidance line, "Future self" label, pill lit
material on screen (English): laid `"Okay, lesson time. What do you want to be able to say today?"`, `"I want to introduce myself."`, then `say("First, tell me your name and where you're from. Like: I'm Mina, I'm from Busan. Your turn!")`
alt (ko): 통화 화면 위쪽에 자기소개하기 과제 네 개가 세로 목록으로 놓여 있어요. 내가 자기소개를 하고 싶다고 하자, 미래의 내가 첫 과제를 알려주며 "I'm Mina, I'm from Busan." 같은 예시를 들려줘요. 미래의 나 라벨과 켜진 픽셀 알약이 보여요.
alt (en): The call screen with a lesson, Introducing yourself, pinned at the top as a list of four challenges. You say you want to introduce yourself, and your future self gives the first challenge with an example line ("I'm Mina, I'm from Busan."). The "Future self" label and the lit pill sit below.

## 02 · Any topic becomes a goal
eyebrow (ko): 나와나로 할 수 있는 것 · 02 / 06
title (ko): 아무 주제나\n목표가 돼요
desc (ko):  배우고 싶은 말을 알려주면,\n**과제 서너 개**로 목표를 세워줘요.

eyebrow (en): What you can do with nawana · 02 / 06
title (en): Any topic\nbecomes a goal
desc (en):  Say what you want to learn to say, and it sets\na goal of **three or four challenges.**

screen: opener already on screen (laid, no typing) → `listen()` → `user("I want to introduce myself.")` → `tutor({ title, rows })`, the lesson strip appears (0/4, row 1 current)
material on screen (English): `say("Okay, lesson time. What do you want to be able to say today?")`, `user("I want to introduce myself.")`
motion: the four rows dropping in one by one
sticker option: the 💡 topic button right of the pill (it opens "What to practice"), from the bar as it is
alt (ko): 미래의 내가 오늘 어떤 말을 하고 싶은지 묻고, 내가 자기소개를 하고 싶다고 답해요. 그러자 위쪽에 자기소개하기 과제 네 개가 세로 목록으로 떠요. 이름과 어디서 왔는지, 하는 일, 좋아하는 것, 한 번에 다 말하기예요.
alt (en): Your future self asks what you want to be able to say, you answer that you want to introduce yourself, and four challenges appear above: your name and where you're from, what you do, what you like doing, all of it in one go.

## 03 · First, it shows you how (the heart)
eyebrow (ko): 나와나로 할 수 있는 것 · 03 / 06
title (ko): 어떻게 말할지\n먼저 알려줘요
desc (ko):  과제마다 예시 한 줄을 들려주고,\n**이제 내 차례**라고 해요.

eyebrow (en): What you can do with nawana · 03 / 06
title (en): First, it shows\nyou how
desc (en):  For each challenge you hear one example line,\nthen **it's your turn.**

screen: checklist with row 1 current (still an empty circle) → `say(...)` → `listen()`
material on screen (English): `say("First, tell me your name and where you're from. Like: I'm Mina, I'm from Busan. Your turn!")`
motion: the example line landing, then the pill opening to listen
alt (ko): 미래의 내가 첫 과제를 알려줘요. 이름과 어디서 왔는지 말해 보라며 "I'm Mina, I'm from Busan." 같은 예시를 들려주고, 이제 내 차례라고 해요. 마이크가 듣기 시작해요.
alt (en): Your future self introduces the first challenge, gives an example line ("I'm Mina, I'm from Busan.") and says it's your turn. The mic starts listening.

## 04 · Say it yourself, until it's right
eyebrow (ko): 나와나로 할 수 있는 것 · 04 / 06
title (ko): 직접 말해요,\n될 때까지
desc (ko):  틀리면 내 말을 바르게 들려주고 다시 해요.\n맞게 말하면 **체크**가 켜져요.

eyebrow (en): What you can do with nawana · 04 / 06
title (en): Your turn,\nuntil it's right
desc (en):  Slip, and it says your line back the right way.\nGet it right, and the row gets **a check.**

screen: `user("I Mina, I from Seoul.")` → `fix({ text: "I'm Mina. I'm from Seoul.", fixes: [{ was: "I Mina", now: "I'm Mina" }, { was: "I from", now: "I'm from" }], note })` → `user("I'm Mina. I'm from Seoul.")` → `tutorTick(0)`
material on screen (English): the two `user()` lines and the fix card's line
fix card note (native, coaching): ko `앞에 I'm을 붙이면 돼요.` / en `Just add "I'm" in front.` (no grammar terms, never "wrong")
optional `say()` between the fix and the retry: `"Almost! I'm Mina, I'm from Seoul. Again?"`
motion: the fix card blooming, then row 1 → green check, struck through, 1/4, row 2 becomes current
alt (ko): 내가 "I Mina, I from Seoul."이라고 말하자 고친 문장 "I'm Mina. I'm from Seoul."이 떠요. 다시 말하니 첫 과제에 초록 체크가 켜져요.
alt (en): You say "I Mina, I from Seoul." and a card shows the line put right, "I'm Mina. I'm from Seoul." You say it again, and the first challenge turns into a green check.

## 05 · Fill them in, and you can say it
eyebrow (ko): 나와나로 할 수 있는 것 · 05 / 06
title (ko): 다 채우면\n말할 수 있어요
desc (ko):  처음 시작해도 괜찮아요.\n레벨이 오르면 **과제도 어려워져요.**
footer (ko): 통화 설정 → 튜터 모드에서 켜요

eyebrow (en): What you can do with nawana · 05 / 06
title (en): Fill them in,\nand you can say it
desc (en):  Just starting? Perfect. As your level grows,\n**the challenges grow with you.**
footer (en): Turn it on in Call settings → Tutor mode

screen: row 1 already checked; laid `"Almost! I'm Mina, I'm from Seoul. Again?"` / `"I'm Mina. I'm from Seoul."` / `"Nice! Now, what do you do? Like: I'm a teacher."` → `user("I'm a nurse.")` → `tutorTick(1)` → `say("Got it! What do you like doing? Like: I like cooking.")` → `user("I like hiking.")` → `tutorTick(2)` → `say("Last one: all of it in one go!")` → `user("I'm Mina, I'm from Seoul. I'm a nurse, and I like hiking.")` → `tutorTick(3)` → `tutorDone()` → `say("All done. You can introduce yourself now! More of this, or a new topic?")`. The whole strip stays in frame; it ends finished (green seal, "All done. You can say it now.").
material on screen (English): the lines above
motion: one short answer per challenge, each one checked as it lands; the last one is the whole introduction in one go, then the closing line
alt (ko): 내가 하는 일과 좋아하는 것을 한 줄씩 말할 때마다 과제가 초록 체크로 바뀌어요. 마지막 과제에서 "I'm Mina, I'm from Seoul. I'm a nurse, and I like hiking."이라고 한 번에 다 말하자 마지막 체크가 켜지고 목록이 완료로 바뀌어요. 미래의 내가 이제 자기소개를 할 수 있다고 말해요.
alt (en): You answer what you do and what you like, one line each, and each challenge turns green as you say it. For the last one you say it all in one go ("I'm Mina, I'm from Seoul. I'm a nurse, and I like hiking."), the last check lands and the lesson shows as finished, and your future self tells you that you can introduce yourself now.

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
alt (ko): nawana 워드마크 아래 "유창한 나에게 언어를 배우세요.", "첫 20분은 무료예요", nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

미래의 내가 선생님이 돼요.

무슨 말부터 해야 할지 막막하다면, 튜터 모드를 켜보세요.
배우고 싶은 말을 알려주면 미래의 내가 과제 서너 개로 목표를 세워줘요.
과제마다 이렇게 말하면 된다고 예시를 들려주고, 이제 내 차례라고 해요.
틀리면 바르게 고쳐 들려주고, 맞게 말하면 체크가 켜져요.
주제는 뭐든 괜찮아요. 자기소개도, 카페 주문도요.

처음 시작하는 사람에게 딱이에요. 레벨이 오르면 같은 주제라도 과제가 어려워져요.

통화 설정 → 튜터 모드를 켜세요.
첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #영어초보 #스피킹 #nawana

(≈ 330 chars)

## Instagram caption (en)

Your future self just became your tutor.

Not sure what to say first? Turn on tutor mode.
Name anything you want to learn to say, and it sets a goal of three or four challenges.
For each one, you hear an example line, then it's your turn.
Slip, and it says your line back the right way. Get it right, and the row is checked off.
Any topic works: introducing yourself, ordering at a café, your own plans.

Perfect if you're just starting. As your level grows, the same topic brings harder challenges.

Turn it on in Call settings → Tutor mode.
Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #englishforbeginners #languagelearning #nawana

(≈ 650 chars)

## Threads (ko)

미래의 내가 대화 상대에서 선생님이 됐어요.

튜터 모드를 켜고 배우고 싶은 말을 알려주면, 과제 서너 개짜리 목표를 세워줘요. 자기소개라면 이름과 출신, 하는 일, 좋아하는 것, 그리고 한 번에 다 말하기. 과제마다 예시 한 줄을 들려주고 내 차례를 줘요. 틀리면 바르게 고쳐 들려주고, 맞으면 체크. 처음 시작하는 사람에게 딱이고, 레벨이 오르면 과제도 어려워져요.

통화 설정 → 튜터 모드. 첫 20분은 무료예요. nawana.app

(≈ 250 chars)

## Threads (en)

My future self isn't just a talking partner now. It's my tutor.

Turn on tutor mode and name anything you want to learn to say. It sets a goal of three or four challenges. Introducing yourself: name and hometown, what you do, what you like, then all of it at once. Each one starts with an example line, then it's your turn. Slip, and you hear it right; nail it, and it's checked off. Great if you're just starting.

Call settings → Tutor mode. First 20 minutes free. nawana.app

(≈ 475 chars)

## Community series entry (refresh e06)

cat `talk`. Replace e06's title/tagline and slides; no second tutor episode. Editing
`series.json` changes the live site → founder approval.

ko: { title: "튜터 모드", tagline: "미래의 내가 선생님이 돼요" }
en: { title: "Tutor mode", tagline: "Your future self becomes your tutor" }

---

## Open questions (for the lead)

1. **Checklist language.** In the app the lesson title and checklist rows are written in the
   NATIVE language (`TutorPlanner`), so I put Korean rows on the ko version and English rows on
   the en version, with the dialogue English on both. The exact row wording is mine (the
   planner writes its own each time); confirm the designer uses these strings.
2. **Fix card note.** "앞에 I'm을 붙이면 돼요" / "Just add "I'm" in front" is sample coaching text
   I wrote; the brief only says the tutor never uses grammar terms or "wrong". Swap if the kit
   has a canned note.
3. **"맞게 말하면 체크".** Card 04 compresses "once more, then next challenge" into "get it right →
   check". The app checks the row when no mistake is found AND the line did the challenge, and
   the tutor still asks for it once more. I left "once more" out of the card to keep one idea;
   say if you want it back.
4. **Hashtags.** Added #영어초보 / #englishforbeginners for the entry-level lead. These name the
   audience, not the reader's grade; drop them if the reviewer reads them against BRAND.
5. **Approval.** Captions, Threads and the e06 series edit need the founder's OK before posting.
