# brief — 2026-10-25-tutor-goal (v2, founder rework 2026-10-26)

The v1 piece (in `_old/`) missed the feature. It sold "your call becomes a lesson / until
you nail it" to someone who can already build sentences, and told the team never to call
it a tutor. The founder's correction, in his words:

> "Basically, the future self becomes your tutor, not just a talking partner. And it really
> helps you complete the goal your tutor set. There are three or four challenges. It gives
> you guidance and then asks you to practice. You can pick any topic you want, and it
> creates the challenges for you. That's perfect for absolute beginners. It can be used by
> advanced users as well, but it's more of an entry-level feature."

Series: **나와나로 할 수 있는 것** · cat `talk`. Refreshes the tutor slot (e06), no new episode.
Formats: ONE Instagram carousel (6 cards) + a Threads cut (first 5) + a **newsletter card**
for the release mail (`newsletter.md`, see bottom).

## One message

미래의 내가 대화 상대에서 **선생님**이 돼요. 배우고 싶은 걸 말하면 과제 3–4개짜리 목표를
세우고, 과제마다 이렇게 말하면 된다고 알려준 뒤 직접 말해 보게 해요.

(EN intent: your future self stops being just someone to talk to and becomes your
**tutor**. Name anything you want to learn to say; it sets a goal of 3–4 challenges, shows
you how to say each one, then has you say it yourself.)

The ROLE CHANGE is the hook: talking partner → tutor. Everything else hangs off it in this
order: goal → challenges → guidance → you practise → checked off.

## Who it's for (founder decision, overrides BRAND's usual "not for zero" floor FOR THIS FEATURE)

**Entry-level first.** The person who opens a free talk and freezes: "무슨 말을 해야 할지
모르겠어." Tutor mode doesn't wait for them to carry a conversation; it tells them what to
say and walks them through it. Founder: perfect for absolute beginners. Say that plainly
(처음 시작하는 사람에게 딱이에요 / perfect if you're just starting). One secondary beat (outro
caption or card 5): higher levels get harder challenges on the same topic. Don't make it the
lead.

Reviewer: the founder approved the beginner framing in this conversation; don't flag it
against the BRAND floor. Still no "zero to fluent" promise.

## Proof in the app (verified in code 2026-10-26)

- **Switch:** Call settings (the slider button left of the pill) → **튜터 모드 / Tutor mode**
  (graduation-cap icon), off by default. Also on the setup sheet shown before the very first
  call. App footer text: "Pick a topic and your future self teaches it step by step, until
  you can say it without a mistake."
- **It opens by asking the goal**, in the learner's own cloned voice. EN opener verbatim:
  "Okay, lesson time. What do you want to be able to say today? Tell me, or pick a topic
  from the button." (ko: "좋아, 오늘은 수업이야. 오늘은 어떤 말을 할 수 있게 되고 싶어?")
- **Any topic:** say it out loud, or tap the 💡 button right of the pill ("What to
  practice": starters + your own situations). "I don't know" → the tutor offers two topics.
- **The plan:** 3 or 4 challenges, each ONE practical thing to say, the last one puts it all
  together. Shown as a checklist pinned above the call, with the lesson title and 1/4.
  Example for a beginner (use this one — it's the most entry-level):
  Lesson "Introducing yourself":
    1. Say your name and where you're from
    2. Say what you do
    3. Say what you like doing
    4. All of it in one go
- **Guidance before practice:** for each challenge the tutor says what it is, gives ONE
  example line, and asks you to say it about yourself ("Tell me your name and where you're
  from. Like: I'm Mina, I'm from Busan. Your turn."). Stuck or silent → it gives you the
  line to say.
- **Practice:** a slip → it says your own line back the right way and asks again (no
  grammar terms, never "wrong"). Right → "once more" so it sticks, then the next challenge.
  The app (not the tutor's mood) checks the row off: no mistake found AND the line did the
  challenge.
- **Done:** "All done. You can say it now." Then: a bit more of this, or another topic. The
  lesson is saved in your review book. Ending the call is always yours.
- An unfinished lesson picks up next call (21 days).
- **Level changes what you practise:** A1 one fact per sentence → A2 two facts/a reason →
  B1 reasons, stories → B2 opinions → C1 managing the conversation.

## Outline (cover → 4 body → outro)

1. **Cover — the role change.** 미래의 내가 / 선생님이 돼요 (EN: Your future self / becomes
   your tutor). Sub: 대화 상대에서 선생님으로. 목표를 세우고, 하나씩 가르쳐줘요.
   Screen: `nw-call` with the 4-challenge checklist laid and the opener bubble ("Okay,
   lesson time. What do you want to be able to say today?"), Future self label + lit pill.
2. **아무 주제나 말하면 목표가 돼요.** You say "I want to introduce myself"; the checklist of
   4 challenges appears.
   Screen: `say(opener)` → `user("I want to introduce myself.")` → `goals([4 rows])`.
3. **먼저 이렇게 말하면 된다고 알려줘요.** The guidance beat (NEW vs v1, this is the heart):
   the tutor names challenge 1 and gives the example line, then "your turn".
   Screen: `say("First, tell me your name and where you're from. Like: I'm Mina, I'm from
   Busan. Your turn!")` → `listen()`.
4. **직접 말해 보고, 될 때까지 같이.** You try, small slip, it says it back right, you say it
   again, row 1 ticks green.
   Screen: `user("I Mina, I from Seoul.")` → `fix({...})` → `user("I'm Mina. I'm from
   Seoul.")` → `tick(0)`.
5. **하나씩 채우면, 이제 말할 수 있어요.** Rows 2–4 tick; last row = all together. Line: 처음
   시작해도 괜찮아요. 레벨이 오르면 과제도 어려워져요.
   Screen: `tick(1..3)` and the final say: "All done. You can introduce yourself now."
6. **Outro** (fixed): wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" ·
   nawana.app. CTA in caption: 통화 설정 → 튜터 모드를 켜세요.

## Kit / fidelity

No tutor capture and no tutor-strip screen in the kit. Build on `nw-call` as v1 did: the
goals chip row stands in for the checklist (empty circle → green check). On-screen
dialogue is English MATERIAL; chrome in the reader's language. The fix card is
`call.fix(...)`. Don't draw a new screen. Sample names only (Mina), never a real user.

## Newsletter (`newsletter.md`, copywriter)

A feature card for `scripts/release-mail.py`'s FEATURES list, in its exact tuple shape:
`(color, tag_ko, title_ko, body_ko, tag_en, title_en, body_en)`. Korean in **합니다체** (a
letter from the founder), English native, no em dashes, 3–4 sentences each, and it ends on
where the switch is. Also a longer version (one paragraph + the 4-step example as a short
list) in case the founder wants tutor mode as the newsletter's lead story. Do NOT edit
release-mail.py; another session has it open.
