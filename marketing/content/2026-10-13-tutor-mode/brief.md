# brief — 2026-10-13-tutor-mode

Series: **나와나로 할 수 있는 것** · cat `talk` (sits beside e04 교정 / e05 통화가 교재로).
Suggested episode id: **e06** (the open slot in the talk run) — publisher/lead to confirm.
Format: ONE Instagram/Threads carousel (founder-fixed). 6 cards.

## One message

Turn on **튜터 모드 (수업)** and your fluent self stops just chatting and runs a real lesson —
every time you say something it teaches, saying the line back the right way **out loud in
your own voice**, then asks a question built so you use what it just taught.

(Reader takeaway, intent only — copywriter renders ko/en natively. The emotional core is
**내 목소리가 선생님이 된다**: your own fluent voice, teaching you. The call-to-action is
**켜세요** — the mode is off until you turn it on.)

## Who it's for

The learner who can build a sentence but wishes someone would just *teach* them instead of
only chatting. Concretely: someone who has done a few free talks, feels the call is "nice,
but am I actually getting better?", and wants a lesson — the right line shown to them, a
theme walked one step at a time — not just a friendly conversation. This is nawana's honest
floor (building a sentence, stumbling; never absolute zero). It is a mode you **switch on**
when you want to be taught, not a grade the app assigns you.

## Why now

- **1.1.9 ships 튜터 모드 (수업)** — the one strong new feature of this release. Autopilot
  upload beat; announce it, and tell people where the switch is.
- It's the natural next beat after e04 (교정 — "틀려도 괜찮아, 유창한 내가 고쳐 말해줘요").
  e04 said mistakes get fixed inside a normal call; **튜터 모드 turns the whole call into a
  lesson**: the fluent self leads a theme, teaches on *every* turn (not only when you slip),
  and builds the next question so your answer reuses what it just taught.

## Proof in the app (all real behaviour)

Source of truth: `CLAUDE.md` "Coach mode — the listening moment, used" (the Tutor mode
paragraph), `FutureVoice/Services/CoachMode.swift` (`TutorMode`),
`FutureVoice/Services/ConversationEngine.swift` (`tutorBlock`).

Everything is built from the existing **`nw-call`** kit screen — no new screen — scripted
with its real API: `say()` (fluent self speaks, pill blooms, words light up), `listen()`
(the empty "Listening…" bubble), `user()` (the learner's words arrive).

**The teaching lives INSIDE the fluent self's spoken line** (`say()`), as a normal spoken
bubble in the learner's own cloned voice — never in a separate correction card and never in
a side surface. Every tutored turn, from `tutorBlock`, has two parts in one spoken line:
1. feedback on what you just said — exactly one of:
   - a mistake → your sentence said the right way ("We'd say: I go hiking with my friends."),
   - correct but stiff → the more natural way ("Even more natural: I'm into hiking."),
   - correct and natural → a short "Good." plus one step up (more useful, or more casual /
     polite: "With friends, just: I'm Eunggyu."),
2. then a practice question built so your answer uses what it just taught.
No repeat-after-me; the lesson moves on to the next theme ("Now let's talk about your work.").

So the carousel rides `nw-call` and carries the teaching in `say()` bubbles. The
`say()`/`user()` beats to script:
- `say()` leads a theme without being handed a topic ("Let's start with introducing
  yourself. What's your name?").
- `user()` says something half-wrong → `say()` teaches it back aloud and asks the next thing.
- `user()` says something correct → `say()` gives "Good." + one step up, then the next question.

Facts that must stay exactly true:
- Tutor mode is a **toggle in call settings** (graduationcap icon, labeled 튜터 모드 /
  Tutor mode), not a new tab/screen. **OFF by default for everyone** — the message is "turn
  it on," never "it's already on."
- The teaching is **spoken aloud in the learner's own cloned voice**, carried in the fluent
  self's dialogue line. That own-voice beat is the hook — not that corrections exist (they
  already do in any call).
- A tutored call is a **PRACTICE call**: not graded, out of the assessment, and nothing said
  counts as "used" — pressure-free. But **minutes, streak, and corrections→cards still
  count**. Say "practice, not graded," never a flat "it doesn't count."
- Flipping it mid-call applies from the **next** call (it's fixed in the call's prompt).

Keep OUT of this piece (these belong to the OLDER Coach mode, a different toggle):
the `fix` correction card (✕ was / ✓ now), "이렇게 말해 보세요 / Try saying", "써 볼 단어 /
Try using", the "썼어요 ✓ / Used it" goal chip, and the `coach` pose. None appear here.

## Outline (cover → 4 feature → outro; one line each = what it says / what the screen does)

1. **Cover** — "수업을 켜면, 미래의 내가 선생님이 돼요." → `nw-call`, fluent self mid-teaching
   `say()` line, Futureself pill lit, words lighting up. Must read as a still in the IG grid.
   Light motion only.
2. **미래의 내가 수업을 이끌어요** — you don't have to bring a topic; it leads one theme at a
   time and starts the lesson. → `nw-call`: `say()` opens a theme ("Let's start with
   introducing yourself. What's your name?") → `listen()`. Sets up that this is a lesson.
3. **틀리면, 맞는 말을 내 목소리로 들려줘요** *(the hero)* → `user()` says it half-wrong
   ("I go to hiking with my friends.") → `say()` teaches it back **out loud in your own
   voice** ("We'd say: I go hiking with my friends. Where do you usually go?"). The teaching
   is the SPOKEN bubble — no card. Motion/video card. Copy must name "내 목소리로" / "spoken
   aloud."
4. **맞아도, 한 걸음 더** — right isn't the end; it shows a better, more useful way. →
   `user()` says something correct ("My name is Eunggyu.") → `say()` gives "Good." + one step
   up, still in the spoken bubble ("Good. With friends, just: I'm Eunggyu. What do you do?").
   Motion/video card.
5. **그 말을 바로 쓰게 묻고, 넘어가요 — 부담 없이** — every turn ends with a question built so
   you reuse what you were just taught, then the lesson moves on; it's a practice call, so
   there's nothing to lose. → `nw-call`: `say()` ends on the practice question, `user()`
   answers using the taught line, and the theme moves on ("Now let's talk about your work.").
   State the switch here: it's off until you turn it on — 설정에서 튜터 모드를 켜세요.
6. **Outro** — standard: wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" ·
   nawana.app.

No sticker and no before/after layout: the whole point is that the teaching is a spoken line
in your own voice, so it stays on the live `nw-call` screen. (A separate correction card
would pull this piece back toward Coach mode — don't add one.)

## Channels

- **Instagram carousel** (default): 6 × 1080×1350. Cover + card 5 + outro as PNG; cards 3 and
  4 as 8–12 s video loops of the `say()`→`user()` teaching beat (`record.mjs`). Caption hook =
  the one message; 3–5 ko+en hashtags (#영어회화 #영어공부 #스피킹 …). The caption must say
  where the toggle is (call settings, graduationcap) and that it's off until you turn it on.
- **Threads**: first 5–6 cards, shorter conversational text (not the IG caption pasted).
- **Community series**: mirror as the next talk entry (e06), 720×900 slides, same day.

## Risks (check before ship)

- **Do NOT say "on by default."** Tutor mode is OFF by default for everyone — the message is
  "turn it on." (On-by-default is the DIFFERENT, older Coach mode toggle; it must not appear
  in this piece.)
- **Do NOT borrow Coach mode surfaces or language.** No `fix` card, no "이렇게 말해 보세요",
  no "써 볼 단어", no "썼어요 ✓". The teaching is a spoken `say()` line in the learner's own
  voice — keep the proof there.
- Don't say "now you can hear your corrections" — corrections already happen in any call. The
  new thing is a **sustained lesson**: the fluent self leads, teaches on every turn, and asks
  questions built to reuse what it taught. Frame around "a lesson," not "a new ability to be
  corrected."
- "Practice call" wording: not graded / pressure-free — but minutes, streak, corrections→cards
  still count. Don't overclaim "it doesn't count."
- Teaching lines are MATERIAL → target language (English by default) in the app's `say()`
  bubbles; the ko/en slide chrome around them is the reader's language.
- Kit sample sentences (names, three meetings a day, busy week) are **sample data** — never
  present as a real user, result, or stat. Don't use the founder's name on a public slide;
  pick a neutral sample name.
- Don't grade the reader ("for beginners" / "the beginner mode"). Say it as *a lesson you can
  switch on when you want to be taught*.

## Success signal

Saves first (a how-it-works piece earns saves) and shares; profile visits → link taps →
installs. Watch comments/replies for "어떻게 켜요?" / "where's the toggle" — a sign the lesson
framing landed and people want it (and the cue to make sure the caption answers it).
Community: views on the e06 entry vs the e04 교정 entry.
