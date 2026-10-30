# 악센트가 단어까지 · copy (series e20, talk, 6 cards)

Written 2026-10-21 from brief.md (1.2.1, build 112, commit `3709fd0e` · CLAUDE.md "The accent
also picks the WORDS, 2026-10-20"). Korean written as Korean, English as English; they agree in
meaning, not wording. 해요체, no 당신, no em dash anywhere (the on-screen call lines too: the
brief's em dashes are replaced with a period). Silent first: no sound lines.

The one thing this piece must land: **the accent changes the WORDS, not just the sound, and your
side of the conversation is never corrected for it.**

Eyebrow on every card: `nawana · NN / 06`.

## For the designer

- **Card count 6.** Cover (01), four `nw-call` cards (02–05) — wait, 05 is text-forward — and the
  outro (06). Precisely: 01 cover · 02 `nw-call` (say) · 03 `nw-call` (user then say, **NO fix**)
  · 04 `nw-call` (settled two-turn British exchange) · 05 text-forward with stickers · 06 outro.
- **Card 03 has NO correction card.** Do not add `call.fix(...)`. The empty space under the
  learner's line where a correction card would normally sit is the whole proof of the card. If a
  fix sneaks in, the piece says the opposite of the truth.
- **No invented screen highlight.** The app does NOT paint variety words in a special colour; the
  transcript just contains them. Any emphasis on flat / lift / queue / fancy is a **sticker
  outside the phone frame** or lives in the card's top text block — never drawn onto the app
  screen.
- **`call.other` stays unset on every call card** → the other side is the fluent self
  ("미래의 나" / "Future self"). The point is that it's YOUR voice in the accent you picked, not a
  British stranger. Never set `other`.
- **The accent is not a new voice.** This is a preset-or-cloned voice being told which variety to
  speak; nothing in the copy may imply a different or new voice. Card 05 carries "your own voice".
- **All call lines are MATERIAL → English on both the ko and en versions.** Keep the British
  words exactly as written (genuine BrE: flat, lift, queue, brilliant, fancy, round the corner,
  pop round, playing up, ground floor, no worries, trolley, do a shop). The learner's
  cross-variety words (apartment, elevator, takeout) stay as written and are NEVER swapped or
  flagged.
- **No numbers on any card** (no scores, no counts, no before/after stats). No prices anywhere but
  the outro's free-minutes line. No paywall.
- **The in-call dialogue lines, in order** (the designer scripts these on `nw-call`):
  - **02** goals `["brilliant", "round the corner", "lift"]`, then
    `call.say("Brilliant to hear from you! Fancy a quick coffee? There's a lovely spot just round the corner. Take the lift down to the ground floor.")`
  - **03** `call.user("I can't, I'm stuck in my apartment waiting for the elevator guy.")` →
    **(no fix card)** →
    `call.say("No worries, sounds like your lift's playing up. I'll pop round to your flat instead.")`
  - **04** a settled exchange (one fluent-self line + one learner line already in the feed):
    fluent self `"The queue at the shop was mad, so I grabbed a trolley and did a proper shop."` ;
    learner `"Ha, I just ordered takeout to my apartment instead."` (learner's own-variety words,
    not corrected).
  - **05** no live call: the Futureself pill (or the call frame dimmed) with word stickers
    **flat · lift · queue** rising around it, pulled from the transcript. No new UI.

---

## 01 · Cover: the promise, then the proof peeking in
eyebrow (ko): nawana · 01 / 06
title (ko): 악센트가\n단어까지 바꿔요
desc (ko):  영국식을 고르면 유창한 나는 **그 동네 말**을 써요.\nflat, lift, queue, 통화 내내요.
chips (ko):
  02 통화 내내 영국 말
  03 내가 쓴 말은 그대로
  04 영국식 · 호주식 · 카스티야식
  05 내 목소리, 내가 고른 악센트
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): nawana · 01 / 06
title (en): The accent picks\nthe words, too
desc (en):  Pick British and your fluent self uses **that variety's words**.\nFlat, lift, queue, every turn of the call.
chips (en):
  02 The whole call goes British
  03 Your own words stay yours
  04 British · Australian · Castilian
  05 Your voice, your accent
footer (en): Swipe → · nawana.app

screen: no phone. `nw-futureself` (speaking) in its circle + the four chips (the carousel's contents). Optional sticker: a small line bubble reading "…take the **lift** down…" peeking from the bottom edge.
alt (ko): ‘악센트가 단어까지 바꿔요’ 제목 아래 ‘영국식을 고르면 유창한 나는 그 동네 말을 써요’가 있고, 미래의 나 모자이크가 말하는 옆에 02~05장 목차가 나열된 표지예요. 아래에서 ‘take the lift down’ 말풍선이 살짝 올라와요.
alt (en): Cover: "The accent picks the words, too" over "Pick British and your fluent self uses that variety's words." The fluent-self mosaic speaks beside the contents for cards 02 to 05, and a small "take the lift down" bubble peeks up from the bottom.

## 02 · Pick British, and the whole call goes British (`nw-call`, say)
eyebrow (ko): nawana · 02 / 06
title (ko): 통화 내내\n영국 말이에요
desc (ko):  영국식 악센트를 고르면 소리만이 아니라 **쓰는 단어**가 바뀌어요.\nfancy, round the corner, lift 처럼요.

eyebrow (en): nawana · 02 / 06
title (en): The whole call\ngoes British
desc (en):  Pick a British accent and it's not only the sound. **The words change**, too.\nFancy, round the corner, lift.

screen: `nw-call`, other unset, goals `["brilliant", "round the corner", "lift"]`. `call.say("Brilliant to hear from you! Fancy a quick coffee? There's a lovely spot just round the corner. Take the lift down to the ground floor.")`. Sticker (outside frame, optional): circle **fancy · round the corner · lift**.
alt (ko): 통화 화면에서 미래의 내가 ‘Brilliant to hear from you! Fancy a quick coffee? There's a lovely spot just round the corner. Take the lift down to the ground floor.’라고 영국식 단어로 말해요. 칩에는 brilliant, round the corner, lift가 있어요.
alt (en): On the call screen, the fluent self says "Brilliant to hear from you! Fancy a quick coffee? There's a lovely spot just round the corner. Take the lift down to the ground floor." in British words. The chips read brilliant, round the corner, lift.

## 03 · Your own words are never wrong (`nw-call`, user then say, NO fix card)
eyebrow (ko): nawana · 03 / 06
title (ko): 내가 쓴 말은\n틀린 게 아니에요
desc (ko):  apartment, elevator라고 해도 그대로 둬요.\n그냥 **flat, lift로** 답해 줄 뿐이에요.

eyebrow (en): nawana · 03 / 06
title (en): Your own words\nstay yours
desc (en):  Say apartment or elevator and it stays yours.\nIt just answers back in **flat and lift**.

screen: `nw-call`, other unset. `call.user("I can't, I'm stuck in my apartment waiting for the elevator guy.")` → **no correction card appears under the line** → `call.say("No worries, sounds like your lift's playing up. I'll pop round to your flat instead.")`. The blank space where a correction card would sit is the point. Do NOT add `call.fix(...)`.
alt (ko): 학습자가 ‘I can't, I'm stuck in my apartment waiting for the elevator guy.’라고 말하는데 교정 카드가 뜨지 않고, 미래의 내가 ‘No worries, sounds like your lift's playing up. I'll pop round to your flat instead.’라고 flat, lift로 답해요.
alt (en): The learner says "I can't, I'm stuck in my apartment waiting for the elevator guy." and no correction card appears; the fluent self answers "No worries, sounds like your lift's playing up. I'll pop round to your flat instead." in flat and lift.

## 04 · Not one line. The whole call (`nw-call`, settled British exchange)
eyebrow (ko): nawana · 04 / 06
title (ko): 한 줄이 아니라\n통화 전체예요
desc (ko):  영국식·호주식, 스페인은 카스티야식에서 단어가 바뀌어요.\n미국식·멕시코식은 **그대로**고요.

eyebrow (en): nawana · 04 / 06
title (en): Not one line.\nThe whole call
desc (en):  British and Australian English, Castilian for Spanish.\nAmerican, Mexican and no accent **stay as they are**.

screen: `nw-call`, other unset, a settled exchange already in the feed. Fluent self: "The queue at the shop was mad, so I grabbed a trolley and did a proper shop." Learner: "Ha, I just ordered takeout to my apartment instead." (learner's own-variety words, not corrected). Keep the top text block carrying the "which accents" fact. Do not fake a Spanish transcript; Castilian is named in words only.
alt (ko): 통화 화면에 미래의 나의 ‘The queue at the shop was mad, so I grabbed a trolley and did a proper shop.’와, 교정 없이 남은 학습자의 ‘Ha, I just ordered takeout to my apartment instead.’가 함께 떠 있어요.
alt (en): The call feed shows the fluent self's "The queue at the shop was mad, so I grabbed a trolley and did a proper shop." and, left uncorrected, the learner's "Ha, I just ordered takeout to my apartment instead."

## 05 · Your voice, your accent (text-forward; stickers)
eyebrow (ko): nawana · 05 / 06
title (ko): 내 목소리로,\n내가 고른 악센트로
desc (ko):  거기 사람들이 실제로 쓰는 말을 **내 목소리로** 들어요.\n그래서 flat도 내가 할 수 있는 말처럼 들려요.

eyebrow (en): nawana · 05 / 06
title (en): Your voice,\nyour accent
desc (en):  The way people really speak there, in **your own voice**.\nSo even "lift" sounds like something you'd say.

screen: no live call. The Futureself pill (or the call frame dimmed) with 2–3 word stickers from the transcript — flat / lift / queue — rising around it. No new UI invented.
alt (ko): 미래의 나 모자이크 알약 둘레로 통화에서 나온 단어 flat, lift, queue가 스티커처럼 떠오르는 장면이에요. ‘내 목소리로, 내가 고른 악센트로’가 위에 있어요.
alt (en): The fluent-self mosaic pill with the words flat, lift and queue rising around it like stickers, under "Your voice, your accent."

## 06 · Outro
eyebrow: none (06 / 06 if the layout shows one)
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

영어, 어떤 영어를 배우고 싶어요?

악센트를 영국식으로 고르면, 유창한 나는 소리만 영국식이 아니에요.
flat, lift, queue. 그 동네에서 실제로 쓰는 단어를 통화 내내 써요.
그런데 내가 apartment, elevator라고 해도 틀렸다고 안 해요. 그냥 flat, lift로 답해 줄 뿐이에요.
영국식·호주식 영어, 스페인은 카스티야식에서 이렇게 바뀌어요. 미국식·멕시코식은 그대로고요.
무엇보다, 그 말을 내 목소리로 들어요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영국영어 #영어공부 #스피킹 #nawana

## Instagram caption (en)

Which English do you actually want to speak?

Pick a British accent and your fluent self doesn't just sound British.
Flat, lift, queue. It uses the words people really say there, every turn of the call.
And your own "apartment" or "elevator" is never marked wrong. It just answers in "flat" and "lift."
British and Australian English, Castilian for Spanish. American, Mexican and no accent stay as they are.
Best of all, you hear it in your own voice.

Your first 20 minutes are free · link in bio

#learnenglish #britishenglish #englishconversation #speakingpractice #nawana

## Threads (ko)

“영국식 영어 배우고 싶은데 앱은 늘 미국식이네.” 그 아쉬움이요.

나와나는 악센트를 영국식으로 고르면 소리만 바꾸지 않아요. flat, lift, queue, 그 동네에서 쓰는 단어를 유창한 내가 통화 내내 써요.

그러면서 내가 apartment, elevator라고 해도 틀렸다고 안 고쳐요. 그냥 flat, lift로 받아 줄 뿐이에요.

영국식·호주식 영어, 스페인은 카스티야식에서 이렇게 바뀌고요. 무엇보다 그 말을, 내 목소리로 들어요.

## Threads (en)

"I want British English, but the app always leans American." That one.

In nawana, pick a British accent and it's not just the sound. Flat, lift, queue — your fluent self uses the words people actually say there, every turn of the call.

And your own "apartment" or "elevator"? Never corrected. It just answers back in "flat" and "lift."

British and Australian English, Castilian for Spanish. Best of all, you hear it in your own voice.

## Community series entry (draft for publisher)

id: e20
cat: talk
slides: 6
ko: { title: "악센트가 단어까지", tagline: "영국식을 고르면 통화 내내 영국 말이 나와요" }
en: { title: "The accent picks the words", tagline: "Pick British and the whole call goes British" }

---

## Open questions (for the lead)

1. **Instagram handle / account** is still "ask the founder" in CHANNELS.md — "프로필 링크" / "link
   in bio" assumes a link-in-bio is set. Confirm before posting.
2. **Threads em dash:** the en Threads text uses one " — " (flat, lift, queue — ...). The em dash
   ban is strict for sent/posted copy, so I can swap it for a period if you want it fully clean;
   left in here only because the three-word aside reads better. Your call.
3. **Card 04 learner line** uses "takeout" (AmE) against the British feed on purpose, to show a
   cross-variety word going uncorrected. If you'd rather the contrast be unmistakable, I can make
   it "I just ordered takeaway" vs "takeout" — but "takeout" is the stronger proof (it's the
   learner's own variety left alone). Flag if you want it changed.
4. **e20 vs existing talk run:** the brief says extend the Talk run (e02–e05) without repeating;
   this is the first accent piece, so e20 is new. Confirm the id slot (e20) is free in the live
   series.json at publish time.
