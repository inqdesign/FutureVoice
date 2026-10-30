# brief — 2026-10-25-tutor-goal

Series: **나와나로 할 수 있는 것** · cat `talk` (the core-talking run).
This is the **tutor-mode REDESIGN** — it supersedes the framing of
`2026-10-13-tutor-mode` (the old "여러 주제를 가르쳐주는" tutor, now retired in the app).
Publisher/lead: don't double-post this as a brand-new episode beside the old one; it
replaces/refreshes that beat. Confirm the episode slot.
Format: ONE Instagram carousel (6 cards) + a Threads cut (first 5). Founder-fixed layout.

## One message

수다가 아니라 수업이에요. 오늘 말하고 싶은 걸 정하면 유창한 내가 작은 과제로 쪼개서,
**제대로 말할 때까지** 같이 연습해요.

(Reader takeaway, intent only — copywriter renders ko/en natively. The shift to land: a
nawana call isn't just friendly chatting anymore — turn on **튜터 모드** and it becomes a
real lesson with a GOAL, and you keep at one line until you can actually say it. Emotional
core: 될 때까지. The teacher is still your own cloned voice — never a stranger, never a
scold. CTA: **켜세요** — it's off until you turn it on, in Call settings.)

## Who it's for

The learner who can build a sentence but comes off a free talk thinking "좋긴 한데, 나
진짜 늘고 있나?" — they want to be TAUGHT toward something, not just talked with. Concrete
moment: someone with a specific thing they want to be able to say ("카페에서 주문 제대로
하기", "면접에서 내 일 설명하기") who, left to free chat, drifts and never nails it.
nawana's honest floor applies (building a sentence, stumbling — not absolute zero). This is
a mode you switch ON when you want a lesson, not a grade the app hands you.

## Why now

- **1.2.4 (build 120) ships the tutor-mode redesign** — the headline feature of the
  release. Autopilot upload beat: announce it and say where the switch is.
- The old tutor (`2026-10-13-tutor-mode`) taught a little on every turn but had no goal and
  no finish line. The redesign makes the call a LESSON WITH A TARGET: you pick what you want
  to say, it becomes 3–4 challenges, and you repeat each one until it comes out clean. "될
  때까지" is the new, sharper promise — worth re-announcing even though "tutor mode" existed.

## Proof in the app (all real behaviour)

Source of truth: `CLAUDE.md` → "Tutor mode — one goal, said until it's nailed (2026-10-24)";
`FutureVoice/Services/TutorMode.swift`, `TutorLesson.swift`, `TutorLessonViews.swift`,
`ConversationEngine.tutorBlock`.

Facts the piece rests on:
- **Off by default**, in Call settings → 튜터 모드. (It replaces the old "several themes" tutor.)
- You pick the topic: the call's own topic, a starter from the 💡 button, or one you say
  out loud ("오늘 뭘 말할 수 있으면 좋겠어?"). Your fluent self turns it into **3–4
  challenges**, the last one putting it all together.
- The **tick is the app's, not the tutor's**: a line clears only when the per-turn
  correction found no mistake AND the line actually did the challenge. On a clean line the
  tutor still asks for it **"once more"** before moving on — you keep at it until you nail it.
- A **checklist is pinned above the call** (folds on tap) showing where you are.
- A finished lesson does NOT end the call — it asks "a bit more, or another topic?" You can
  keep going, switch topic (the talk so far is saved as its own review book), or stop.
  **Ending the call stays yours.**
- Unfinished lessons **resume for 21 days**.
- The level changes WHAT you practise, not how much.
- It's your own cloned voice — your fluent self — teaching you. Never a stranger, never a scold.

### How it maps to the kit (built ONLY from `nw-call` — no new screen)

The `call` screen's **goals chip row** stands in for the TutorLessonStrip checklist: each
chip is one challenge, an empty circle until nailed. `call.goals([...])` lays the checklist;
`call.tick(n)` turns challenge n's circle into a **green checkmark**. `call.fix({...})`
shows the correction card ("say it right until clean"). `call.say()`/`listen()`/`user()`
run the back-and-forth. That's the whole vocabulary this piece needs — nothing else drawn.

## Outline (cover → 4 body → outro)

Each body card is `nw-call`, title = the lesson topic, level chip B1/B2, fluent-self pill.
The checklist (goals row) is visible from card 2 on; motion = the step named.

1. **Cover** — pixel title: 통화가 수업이 돼요 (or 될 때까지). Sub: 오늘 말하고 싶은 걸
   정하면, 유창한 내가 될 때까지 가르쳐줘요.
   Screen: `nw-call` with the checklist already laid (3–4 empty-circle chips), one `say()`
   bubble in the fluent self's voice. Must read as a still in the grid.

2. **고를 수 있어요 — "오늘 뭘 말할 수 있으면 좋겠어?"** The topic becomes a lesson: 3–4
   challenges appear as a checklist above the call.
   Screen: `say()` asks the topic question (or topic picked), then `goals([...])` populates
   the chip row — all empty circles. Motion: the checklist filling in. *(Sticker option: the
   💡 topic button, from the bar.)*

3. **될 때까지 (1) — 틀려도 괜찮아요.** You try the first challenge, it's not quite right; the
   correction card shows the line said the right way.
   Screen: `user()` half-wrong → `fix({ text, note, fixes:[{was, now}] })`. Checklist chip 0
   still an open circle. Caption beat: 틀린 곳만 짚어서, 제대로 말할 때까지.

4. **될 때까지 (2) — 맞게 말하면 초록 체크.** You say it again, clean — the first challenge
   ticks green. And even when it's right, 한 번 더 — you keep at it until you nail it.
   Screen: `tick(0)` → first chip becomes the green checkmark. Motion: the circle → green check.

5. **한 과제씩, 다 채우면.** One by one the checklist fills; the last challenge puts it all
   together. A finished lesson doesn't end the call — 더 할래, 아니면 새 목표? (and the talk
   becomes a review book). 끝내는 건 언제나 내 선택.
   Screen: `tick(1)`, `tick(2)`… the checklist mostly/fully green, last chip = the
   "put-it-together" challenge. Motion: the checks landing one after another.

6. **Outro** (fixed): wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" ·
   nawana.app. Copywriter: fold in the CTA fact — 튜터 모드는 통화 설정에서 켜요 — into the
   caption, not the outro art.

Mark where help is used:
- **Correction card** (card 3) is the key sticker — it carries "제대로 말할 때까지".
- **Green-check tick** (cards 4–5) is the emotional payoff; keep the circle → check motion crisp.

## Channels

- **Instagram carousel** (default): 6 cards, 1080×1350. Cards 2–5 as 8–12 s MP4 loops (the
  checklist filling, the tick landing, the fix card blooming); cover + outro as PNG.
- **Threads**: first 5 cards, shorter conversational text. Lead line = the one message
  ("nawana 통화가 이제 수업이 돼요 — 될 때까지").
- **Community series**: mirror as the talk-run entry that refreshes the old tutor beat (see
  the series note at top). Lead/publisher confirms the episode id; do not stack a second
  tutor episode.

## Risks / must-check

- **No founder input** (autopilot) — reviewer must hard-check every tutor fact against the
  CLAUDE.md "Tutor mode (2026-10-24)" paragraph; the app behaviour changed, and the old
  `2026-10-13-tutor-mode` copy is now WRONG (don't reuse its "teaches on every turn / no
  repeat-after-me" lines — the new mode DOES repeat until clean).
- Any numbers on chips/cards (level, scores) are illustrative kit sample data — never as results.
- Don't claim the tutor grades you or assigns a level; the level only changes WHAT you practise.
- Don't over-promise: honest floor stays (sentence-building, stumbling), no zero-to-fluent.
- The teacher is your own voice — never frame it as "an AI tutor"; the nawana comparison is
  "someone else's voice vs mine."
- "resume for 21 days" and "saved as a review book" are true but hard to SHOW on `call` —
  keep them in caption/Threads text, not forced into a card.

## Success signal

Saves on the carousel (a "I want this" feature beat), profile visits, and community views on
the talk-run entry. Secondary: whether the comments ask "where do I turn it on" — if so the
CTA (Call settings) needs to be louder in the caption next time.
