# 자유 대화가 지난 대화를 기억해요 · copy (series talk, 5 cards)

Autopilot run for 1.3.6 (build 149). Feature = What's New card 2, the founder's approved words.
One message: 며칠 전 통화 얘기를 꺼내면, 유창한 나가 그때 했던 말을 찾아와 거기서부터 이어 가요.
Korean written as Korean, English as English, never translated across. 해요체 in chrome, no 당신,
no em dash anywhere in this file. The fluent self speaks 반말 and never longs. Bubble lines are
MATERIAL (English, the language being learned) and stay English on both versions. Every name and
interview detail is kit sample data, not a real user and not the founder.

Eyebrow on every card: `nawana · NN / 05`.

## For the designer

- **Card count 5.** 01 cover (PNG still), 02 to 04 feature (`carousel.html?solo=N` to `record.mjs`,
  8 to 12 s MP4), 05 outro (PNG still).
- **One screen, one call, three moments.** 02 to 04 all run the SAME `nw-call`
  (`web/kit/screens/call.js`), same conversation, different moment of its flow. No second screen,
  no "memory list" UI (the index and lookup are background, they have no UI). The proof is the
  conversation itself.
- **The talk on screen (material, English on both versions), in order:**
  1. you: "Remember the interview I told you about last week?"
  2. fluent self: "The design studio one? You were sweating the portfolio question. How'd it go?"
  3. you: "I got it. I start in two weeks."
  4. fluent self: "No way, that's huge. So the portfolio part landed in the end?"
- **Emphasis on card 03:** highlight "design studio" and "the portfolio question" in the fluent
  self's line. That one line, naming a detail only the past call held, is the whole proof of
  "remembers". Make 03 the strongest card.
- **No correction, no score, no feedback panel.** This is a free talk, not a drill. The fluent
  self does not grade the interview. Nothing on screen judges the learner.
- **Chrome labels stay the app's own** (해요체): the call header, the pill, "미래의 나" speaker
  label (en: your fluent self / Future self, per the kit's own label).

---

## 01 · Cover (still): the past call carries on
eyebrow (ko): nawana · 01 / 05
title (ko): 지난 통화를\n기억해요
desc (ko):  며칠 전에 한 얘기를 꺼내면, **그때 했던 말**을 찾아와 거기서부터 이어 가요.

eyebrow (en): nawana · 01 / 05
title (en): It remembers\nyour last talk
desc (en):  Bring up something from days ago and it finds **what you actually said**, then carries on.

screen: 타이포 중심. 뒤에 `nw-call` 한 장면을 아주 옅게 깔아도 됨 (스틸로 성립해야 함)
alt (ko): ‘지난 통화를 기억해요’ 제목 아래 ‘며칠 전에 한 얘기를 꺼내면 그때 했던 말을 찾아와 거기서부터 이어 가요’가 적힌 표지예요. 뒤로 통화 화면이 옅게 깔려 있어요.
alt (en): Cover: "It remembers your last talk" over "Bring up something from days ago and it finds what you actually said, then carries on." A call screen sits faintly behind it.

## 02 · You bring up last week's call (setup, live)
eyebrow (ko): nawana · 02 / 05
title (ko): 지난주 통화를\n툭 꺼내요
desc (ko):  "저번에 말한 그 면접" 처럼, 며칠 전 통화 얘기를 **평소 말하듯** 꺼내면 돼요.

eyebrow (en): nawana · 02 / 05
title (en): Just bring up\nlast week's call
desc (en):  Mention a call from days ago the way you'd say it to a friend. **No command to memorize.**

screen: `nw-call`에서 `call.user("Remember the interview I told you about last week?")`가 올라가고, `call.listen()`로 "미래의 나" 가 생각하는 중 (say 직전까지)
sticker: 학습자 버블 하나를 스티커로 띄워도 됨
alt (ko): 통화 화면에 ‘Remember the interview I told you about last week?’라는 내 말이 올라가고, 유창한 내가 대답하기 직전이에요.
alt (en): On the call screen, your line "Remember the interview I told you about last week?" appears, and the fluent self is about to answer.

## 03 · It picks out what you said (payoff, live)
eyebrow (ko): nawana · 03 / 05
title (ko): 그때 한 말을\n집어내요
desc (ko):  그 통화에서 **실제로 오갔던 말**을 찾아와, 거기 있던 디테일까지 집어내요.

eyebrow (en): nawana · 03 / 05
title (en): It picks out\nwhat you said
desc (en):  It pulls up **what was actually said** in that call, down to the detail you'd forgotten it held.

screen: `nw-call`: `call.say("The design studio one? You were sweating the portfolio question. How'd it go?")` — "design studio" 와 "the portfolio question" 강조
alt (ko): 유창한 내가 ‘The design studio one? You were sweating the portfolio question. How'd it go?’라고 답하고, 지난 통화에만 있던 디테일인 ‘design studio’와 ‘the portfolio question’이 강조돼 있어요.
alt (en): The fluent self replies "The design studio one? You were sweating the portfolio question. How'd it go?", with "design studio" and "the portfolio question", details only the past call held, highlighted.

## 04 · It carries on from there (continuation, live)
eyebrow (ko): nawana · 04 / 05
title (ko): 거기서부터\n이어 가요
desc (ko):  어제 한 말을 다시 설명 안 해도 돼요. **지난 통화에 이어서** 오늘 얘기가 계속돼요.

eyebrow (en): nawana · 04 / 05
title (en): It carries on\nfrom there
desc (en):  No re-explaining yesterday. Today's talk **continues the last one**, right where it left off.

screen: `nw-call`: `call.user("I got it. I start in two weeks.")` 올라가고 → `call.say("No way, that's huge. So the portfolio part landed in the end?")`
compare: "매번 처음부터 다시 설명해야 하는 AI 상대"와의 대비는 캡션으로만. 화면에 비교 UI 금지
alt (ko): 내가 ‘I got it. I start in two weeks.’라고 말하자, 유창한 내가 ‘No way, that's huge. So the portfolio part landed in the end?’라며 지난 통화를 이어 대화해요.
alt (en): You say "I got it. I start in two weeks." and the fluent self answers "No way, that's huge. So the portfolio part landed in the end?", carrying the earlier call forward.

## 05 · Outro (still, standard)
eyebrow: none (05 / 05 if the layout shows one)
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

"저번에 말한 그거, 기억해?" 하고 꺼내면, 유창한 내가 진짜 기억해요.

며칠 전 통화 얘기를 평소 말하듯 툭 꺼내 봐요.
그러면 제목 한 줄이 아니라, 그 통화에서 오갔던 말을 찾아와요.
거기 있던 디테일까지 집어내서, 어제 하던 얘기가 오늘 거기서부터 이어져요.
매번 처음 보는 상대가 아니라, 지난 통화를 기억하는 상대예요.

한 적 없는 통화는 지어내지 않아요. 네가 실제로 한 통화만요.
유창한 나와의 자유 대화에서, 며칠 전 통화도 이어서 할 수 있어요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #전화영어 #nawana

## Instagram caption (en)

"Remember the interview I told you about?" In free talk, it actually does.

Bring up a call from days ago, the way you'd mention it to a friend.
It finds what was actually said in that talk, not just the title.
It picks up the details only that call held, and carries on from there.
Not a blank slate every time, but someone who remembers your last call.

It won't invent a call you never had. Only the ones you really made.
Free talk with your fluent self, picking up days later where you left off.

Your first 20 minutes are free · link in bio

#speakingpractice #learnenglish #englishconversation #languagelearning #nawana

## Threads (ko)

AI랑 영어 하다 보면, 저번에 한 말을 오늘 또 설명하게 되지 않아요?

유창한 나와의 자유 대화는 지난 통화를 기억해요. "저번에 말한 그 면접 기억해?" 하고 꺼내면, 그 통화에서 오갔던 말을 찾아와 디테일까지 집어내요. 어제 하던 얘기가 오늘 거기서부터 이어져요.

한 적 없는 통화는 지어내지 않아요. 네가 실제로 한 통화만 기억해요.

며칠 전 통화, 이어서 해 봤어요?

## Threads (en)

Talking to an AI, do you end up re-explaining yesterday every single time?

Free talk with your fluent self remembers your past calls. Say "remember that interview?" and it pulls up what was actually said in that talk, down to the detail, and carries on from there.

It won't make up a call you never had. Only the ones you really made.

Ever picked a talk back up, days later?

## Community series entry

cat: talk
ko: { title: "통화가 이어져요", tagline: "며칠 전 얘기를 꺼내면 거기서부터" }
en: { title: "Talks continue", tagline: "Bring up an old one, pick up from there" }

Board-order placement and the free `e06` id are the lead's call (see Open questions).

---

## Open questions (for the lead)

1. **Series id / placement.** `series.json` runs e01 to e19 with e06 missing. Use e06 for this
   talk entry, or append e20? Both are board-order decisions for the lead. Entry goes live on
   deploy, so founder approval before publish.
2. **Sister piece overlap.** `2026-11-17-free-talk-your-way` (control) ships the same day as this
   (continuity/memory). Confirm both post, and in what order, so captions don't read as duplicates.
3. **Free-minutes recheck on publish day.** `freeTalkSeconds` reads 1200 (= 20 min) today; re-run
   the check before packaging in case `billing-switch.py` moved it.
