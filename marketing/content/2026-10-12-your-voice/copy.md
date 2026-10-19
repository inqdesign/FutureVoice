# 내 목소리로 말하는 나와 통화해요 — copy (voice carousel, 6 cards)

Autopilot run for 1.1.8 (88). The one message: **유창한 나는 내 목소리로 말해요.** The 1.1.8 voice
engine is the reason to say it now, never the subject — no "바뀌었어요 / 업그레이드 / 엔진 / 새로워졌어요",
no vendor name anywhere (brief risk 1). Each card was written in Korean first and then separately in
English, not translated. The fluent self's on-screen lines stay English (casual), as the kit draws them;
every label and description around them is 해요체.

Length target (matching the approved sibling piece): ko descriptions ~40–58 characters, en ~90–150
characters, 2 lines on the render. Titles 2 lines, ~8–10 characters a line.

**For the designer (screens + beats per brief):**
- Eyebrow number → `NN / 06` (01 / 06 … 06 / 06).
- Cover (01): `nw-home` beat 1, the call launcher / ring, one tap to call. Must hold as a still in
  the grid. No price, no number on the cover.
- Cards 02–05: `nw-call` as 8–12 s MP4 loops so the turn-taking and the pill's speaking motion read.
  - **02:** beat 1 only — the opener appears, Futureself speaking. Don't run into the correction here.
  - **03 (hero):** beats 2→3 — the learner's bubble, then the fluent self's answer in the learner's
    voice; goal chips may tick. A small fix card may land WITH the reply (never before it), kept a
    side beat (brief risk 3).
  - **04:** `nw-call` with the Futureself pill speaking (clipped, light palette). Optional small
    `nw-futureself` pill sticker — no comparison sticker (brief). This is where 1.1.8's "more natural,
    more like you" lands, shown as the FEELING, never captioned as an improvement.
  - **05:** the reply bubble appears promptly after the learner's bubble, a natural turn cadence. NO
    number, NO "typing…" or loading UI, NO benchmark (brief risk 4).
- Outro (06): the fixed series outro — Futureself pill speaking (clipped, light), wordmark. One offer
  line only; no plan prices (brief risk 8).
- No accent / voice-settings card (status.md, brief risk 2). Numbers on any `nw-call` screen are kit
  sample data, never user results (brief risk 5). Futureself mosaic clipped inside the pill only
  (brief risk 6).

---

## 01 — Cover: the call launcher, Futureself speaking
eyebrow (ko): 내 목소리로 말하는 나 · 01 / 06
title (ko): 내 목소리로\n나와 통화해요
desc (ko):  탭 한 번이면 유창한 나와 통화가 시작돼요.\n그 목소리는 바로 **내 목소리**예요.
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): In your own voice · 01 / 06
title (en): Call the\nfluent you
desc (en):  One tap, and you're on a call with the fluent you.\nAnd that voice is **your own.**
footer (en): Swipe → · nawana.app

screen: `nw-home` beat 1 (the ring / call launcher)
alt (ko): Talk 탭의 통화 링을 누르면 통화가 시작되는 표지예요. 유창한 내가 내 목소리로 전화를 받아요.
alt (en): Cover: tapping the call ring on the Talk tab starts a call; the fluent you picks up in your own voice.

## 02 — 누가 받는가: the opener, the fluent self speaking
eyebrow (ko): 내 목소리로 말하는 나 · 02 / 06
title (ko): 몇 년 뒤의\n내가 받아요
desc (ko):  외국어가 이미 편해진 몇 년 뒤의 내가,\n**내 목소리 그대로** 전화를 받아요.

eyebrow (en): In your own voice · 02 / 06
title (en): It's you,\nyears from now
desc (en):  A few years on and already fluent, you pick up the phone, sounding **exactly like you.**

screen: `nw-call` beat 1 (opener, Futureself speaking)
material on screen (stays English, casual):
- fluent self (opener): "Hey, it's you, a few years from now. So, how was your week?"
alt (ko): 통화 화면에 미래의 내가 먼저 말을 건네요. ‘Hey, it's you, a few years from now…’ 하고 내 목소리로 인사해요.
alt (en): The call opens with the fluent self greeting first, in the learner's own voice: "Hey, it's you, a few years from now…".

## 03 — 통화 한 통 (hero): take turns, the fluent self answers
eyebrow (ko): 내 목소리로 말하는 나 · 03 / 06
title (ko): 내가 말하면\n유창한 내가 답해요
desc (ko):  전화처럼 번갈아 말해요. 내가 말하면\n유창한 내가 **내 목소리로** 대답해요.

eyebrow (en): In your own voice · 03 / 06
title (en): You talk,\nit answers
desc (en):  Take turns like a real call. You speak, and the fluent you answers, **in your voice.**

screen: `nw-call` beats 2→3 (learner bubble → fluent-self answer; goal chips may tick)
material on screen (stays English, casual):
- learner: "It was a busy week. I go to three meetings a day."
- fluent self: "Three a day? No wonder you sound tired. Which one went best?"
- fix card (side beat, lands WITH the reply): "I **went** to three meetings a day." · note (ko): 지난 일이라 과거형이에요 · note (en): It already happened, so past tense.
- goal chips: busy week · catch up · no wonder
alt (ko): 통화 화면에서 내가 ‘I go to three meetings a day’라고 말하면, 유창한 내가 내 목소리로 이어서 대답해요.
alt (en): On the call screen the learner says "I go to three meetings a day", and the fluent self answers in the learner's voice.

## 04 — 왜 내 목소리일까: feels like you
eyebrow (ko): 내 목소리로 말하는 나 · 04 / 06
title (ko): 왜 하필\n내 목소리일까요?
desc (ko):  원어민을 따라 하면 연기 같아요. 내 목소리로 들으면\n**‘나도 이렇게 말할 수 있구나.’** 싶어요.

eyebrow (en): In your own voice · 04 / 06
title (en): Why your\nown voice?
desc (en):  Copying a native feels like acting. In your own voice, it becomes **“I can say it like that too.”**

screen: `nw-call`, Futureself pill speaking (clipped, light); optional `nw-futureself` pill sticker
material on screen (stays English, casual):
- fluent self: "I'd love to tell you about my project."
alt (ko): 유창한 내가 ‘I'd love to tell you about my project’를 내 목소리로 말해요. 따라 하는 게 아니라 내 목소리라 더 자연스러워요.
alt (en): The fluent self says "I'd love to tell you about my project" in the learner's own voice. It isn't a copy, it's them, which is what makes it feel natural.

## 05 — 대답이 바로 와요: fast, shown not measured
eyebrow (ko): 내 목소리로 말하는 나 · 05 / 06
title (ko): 말을 멈추면\n바로 대답해요
desc (ko):  말을 멈추면 유창한 내가 바로 대답해요.\n**기다리는 어색함 없이**, 진짜 통화처럼요.

eyebrow (en): In your own voice · 05 / 06
title (en): Stop, and\nit answers
desc (en):  Stop talking and the fluent you answers right away, **no awkward wait**, like a real call.

screen: `nw-call` — the reply bubble lands promptly after the learner's bubble (natural turn cadence)
material on screen (stays English, casual):
- learner: "Honestly, I'm a little nervous about the demo."
- fluent self: "That makes sense. Want to run the opening line by me?"
alt (ko): 내가 말을 멈추자마자 유창한 내가 이어서 대답해요. 로딩 표시 없이 통화가 자연스럽게 흘러가요.
alt (en): The moment the learner stops, the fluent self answers; the call flows on with no loading indicator.

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
alt (ko): nawana 워드마크 아래 ‘유창한 나에게 언어를 배우세요.’와 ‘첫 20분은 무료예요’, nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

내 목소리인데, 지금의 나는 아직 못 하는 말을 유창하게 하고 있어요.

몇 년 뒤, 외국어가 이미 편해진 나예요.
탭 한 번이면 전화하듯 통화가 시작되고,
내가 말하면 그 목소리가 바로 대답해요.
더듬거린 말은 통화하면서 자연스럽게 다듬어져요.

원어민을 따라 하는 게 아니라, 내 목소리라서 ‘나도 이렇게 말할 수 있구나’ 싶어져요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #외국어공부 #nawana

(≈ 230 chars)

## Instagram caption (en)

It's my own voice, saying the things I can't say yet, fluently.

It's you, a few years on, already comfortable in the language.
One tap and you're on a call, like a real one.
You speak, and that voice answers right away.
The parts you stumble on get smoothed over as you go.

It isn't copying a native speaker. It's your own voice, and it turns into "I could say that too."

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #nawana

(≈ 490 chars)

## Threads (ko)

원어민 발음을 따라 하다 보면, 어쩐지 연기하는 기분 들 때 있지 않아요?

나와나에선 그 목소리가 내 목소리예요. 몇 년 뒤, 외국어가 이미 편해진 내가 전화를 받아요. 내가 말하면 바로 대답하고, 더듬은 말은 통화하면서 자연스럽게 다듬어져요.

내 목소리로 유창하게 말하는 나를 한 번 들어 보면, 생각보다 가까워요.

첫 20분은 무료예요. nawana.app

(≈ 190 chars)

## Community series entry

cat: talk. **FLAG (brief): overlaps `2026-10-11-what-you-can-do` cards 02–03 (the call + 왜 내 목소리).**
Ship this as its own episode only if the founder wants a voice-focused entry; otherwise point to the
existing episode. If it ships, kept tightly about the voice so it's distinct.

ko: { title: "내 목소리로", tagline: "유창한 내가 내 목소리 그대로 전화를 받아요" }
en: { title: "In your own voice", tagline: "Your fluent self picks up, sounding exactly like you" }

---

## Open questions (for the lead)

1. **Community entry overlaps the 10-11 piece** (brief flagged it). The {ko/en} above is written to be
   distinct — voice only, no Watch/Review/corrections — but it still shares the call + "왜 내 목소리"
   beats with `2026-10-11` cards 02–03. Confirm: ship as its own `talk` episode, or extend that one.
2. **Series eyebrow.** I named the carousel "내 목소리로 말하는 나" / "In your own voice" (no existing
   series id). Confirm the wording, or map it to an episode id if it goes on the community page.
3. **Card 03/05 material lines.** 02–03 reuse the kit's `nw-call` sample ("three meetings a day",
   "went", the chips) for continuity with the sibling piece; 05 adds two short lines ("…nervous about
   the demo" → "…run the opening line by me?") to show one clean turn without a correction. Confirm the
   kit's `nw-call` can render the 05 pair, or I'll fall back to the 03 lines without the fix card.
4. **"Fast" with no number.** Card 05 and the captions show the reply landing on a natural turn and
   never state a figure or draw a loading UI (brief risk 4). Confirm the recorded loop reads as "right
   away" at feed speed without one.
5. **Platform-neutral.** No OS or platform named anywhere (brief risk 10); the daily call isn't in this
   piece, so nothing claims "rings on silent". Nothing to verify unless the founder wants a platform tag.
6. **Captions + Threads need approval** before posting (nawana never posts without the founder's OK).
   Both are well under limits (IG en ≈ 490, Threads ko ≈ 190).
