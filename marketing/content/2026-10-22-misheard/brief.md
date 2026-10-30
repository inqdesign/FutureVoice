# brief — misheard (1.2.2 / build 118)

- **stage:** brief → copy
- **channels:** IG carousel (6 cards) + Threads (first 4–5) + community series entry (new,
  cat `practice`). Extends the Review run (e10 오늘의 복습, e11 다시 말하기, e12 섀도잉,
  e13 단어장, e14 표현, e15 문장 카드, e16 주간 시험). This lives ON the 문장 카드 (e15)
  but is a distinct beat: e15 is "what a sentence card is"; this is "when the card quotes
  you wrong, you can say so." Not a repeat.
  - **Episode id:** e20 is claimed by accent-words, e21 by coach-suggestion (both in
    progress). This is likely **e22** — lead to confirm no collision before the publisher
    drafts the series entry.

## The one message

복습하다 카드의 "내가 한 말"에 **내가 안 한 말**이 적혀 있으면, 오른쪽 위 ⋯ 한 번으로
"잘못 들림"이라고 말할 수 있어요. 그 문장은 점수에서 빠지고, 거기서 나온 카드도 알아서
정리돼요. 음성 인식이 가끔 잘못 알아들어도 — **내가 하지 않은 말로 채점받지 않아요.**

(EN intent, for the en column — copywriter renders natively, never translates: When a
review card's "You said" line shows words you never actually said, one tap on the ⋯ in the
corner lets you mark it "misheard." That line drops out of your score, and the cards it
spawned clean themselves up. Speech recognition slips sometimes — and you're never graded
on words you didn't say.)

If the piece can only land one feeling: **fair, and in your control.** The recognizer isn't
perfect, so you get the final word on what counts as something you said.

## Who it's for

The learner working through their review deck who hits a card that misquotes them — "내가
한 말" shows a garbled line they know they never said, and it stings to be "corrected" on it.
Concretely: 복습 카드에 내가 안 한 말이 적혀 있는 걸 보고 "이건 내가 한 말이 아닌데…"
싶었던 사람. Anyone who has talked to a voice assistant knows the feeling of being
misheard; this says nawana knows it too, and does something about it.

Honest floor respected: this is someone already reviewing their own talks — not an absolute
beginner. The piece sells honesty and control, never fluency.

## Why now

1.2.2 (build 118) ships it — commits `394249c3` (the action) + `f4ed167b` (the menu moved to
the card's corner, red text removed). CLAUDE.md anchors: DrillStore "flagging a turn as
misheard deletes the cards minted from it"; say-it-again "a turn flagged misheard is dropped
outright." nawana already drops misheard turns quietly in the background; this build puts the
**one-tap control on the card itself**, where you're actually reading the misquote. Before,
you could only do this from the book's Grammar page (a swipe) or the transcript — two screens
away from the deck where the sting happens.

## Proof in the app

- **Screen:** `web/kit/screens/review.js` (`nw-review`), the **`card` pose** — the blue
  sentence card with "내가 한 말 / You said" and the line. Grounded in
  `marketing/captures/review-due.png` + `drills.png`.
- **The misheard ⋯ menu has NO capture yet** (it's new in build 118). Per `status.md`, the
  designer may add a faithful pose to `nw-review` — the ⋯ pinned to the card's **top-right
  corner** (SF `ellipsis.circle`), tapped to open a one-item menu **"잘못 들림 — 채점에서
  제외" / "Misheard — exclude from scoring"** (icon `mic.slash`), then the card leaving the
  deck. If no pose lands in time, tell the story through the `card` pose plus a **sticker**
  of the ⋯ menu beside the phone. **Do NOT draw a new screen.**
- **Real, verified behaviour (don't drift from this):**
  - The ⋯ sits in the card's **corner**, same place whatever the sentence length
    (`f4ed167b`). It is a **plain menu item, not red/destructive** (`f4ed167b`, founder:
    red read poorly). Never draw it as red text or a scary warning.
  - One item only: **잘못 들림 — 채점에서 제외** (`mic.slash`). The Korean label is
    confirmed in the catalog (`잘못 들림 — 채점에서 제외`).
  - Tapping it: the turn leaves scoring, its slips go, the grammar score is recomputed, the
    cards minted from that turn are deleted, the weekly assessment re-runs, and the same
    turn's cards drop out of **this** deck run. **No review rep is counted** — nothing was
    reviewed. (All internal — don't put the mechanics as a spec on a slide; say "the app
    cleans up after itself.")
  - It appears only on a card that came from a real talk turn (a correction card). The
    learner **decides and taps** — nawana does not auto-detect a mishearing. This is a
    control you reach for, honesty on your terms.
- **The "You said" sample on the card must read like a RECOGNIZER slip, not a learner
  mistake** — a dropped word, a garble, a wrong homophone. The kit's own capture line
  ("Feel something around Nirvana the app that I'm gonna be working on") already reads like
  a mishearing and is perfect for the problem card. Do not use a clean grammar-error sample
  for the misheard story, or it looks like the learner just made a mistake.

## Outline (6 cards)

**Card 1 — Cover** (still PNG; must read in the grid)
- Says: 내가 안 한 말로 채점받지 않아요. / Never graded on words you didn't say.
- Screen: none (cover layout). Series eyebrow + pixel title. Optional sticker: the ⋯ corner
  menu peeking in, or a struck "내가 한 말" line.

**Card 2 — The problem** (`nw-review`, `card` pose)
- Says: 복습하다 보면, "내가 한 말"에 내가 안 한 말이 적혀 있을 때가 있어요 — 음성 인식이
  가끔 잘못 알아듣거든요. / Reviewing, you sometimes find words under "You said" that you
  never actually said — speech recognition slips now and then.
- Screen: the blue sentence card, "내가 한 말 / You said" with a misheard-looking line. This
  is the sting — let the misquote sit there.

**Card 3 — The one-tap fix** (`nw-review`, `card` pose with the ⋯ menu open, or `card` +
sticker)
- Says: 오른쪽 위 ⋯ 한 번, "잘못 들림". 그게 다예요. / One tap on the ⋯ in the corner —
  "Misheard." That's it.
- Screen: the ⋯ at the card's top-right corner, the single menu item "잘못 들림 — 채점에서
  제외" open. Keep it calm — a normal menu, no red, no warning tone.

**Card 4 — The payoff** (`nw-review`, `card` pose, card leaving the deck)
- Says: 그 문장은 점수에서 빠지고, 거기서 만들어진 카드도 알아서 사라져요. 뒤처리까지 앱이
  해줘요. / That line drops out of your score, and the cards it created clean themselves up.
  The app handles the rest.
- Screen: the card sliding out of the deck (reuse the deck's existing file-away motion), the
  count ticking down. Don't invent a new animation — lean on the deck's own card-leaves move.

**Card 5 — Fair, and in your control** (`nw-review`, `card` pose, or a clean deck)
- Says: 인식이 완벽하진 않으니까, 뭘 "내가 한 말"로 칠지는 내가 정해요. 공정하게, 내 손에서.
  / The recognizer isn't perfect, so you decide what counts as something you said. Fair, and
  in your hands.
- Screen: the deck looking clean/settled, or the card back. This is the feeling card — sell
  trust and control, not a feature list. The underlying promise (CLAUDE.md): nawana never
  grades you on what a machine put in your mouth.

**Card 6 — Outro** (standard outro)
- Wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" · nawana.app. No price
  claims beyond the free-minutes line.

## Risks / things to check before ship

- **Don't overclaim.** This is a small, considerate feature — not a revolution. No "AI
  finally understands you," no "perfect accuracy." The honest frame: recognizers slip
  sometimes, and now you can say so. Sell the feeling (fair, in control), not a breakthrough.
- **Never red, never a warning.** `f4ed167b` removed the destructive red text on purpose.
  Draw the menu item as a plain, quiet option. The tone is considerate, not alarming.
- **It's a ⋯ in the card's CORNER, not a swipe and not beside the play button.** The
  book's Grammar page swipe still exists separately; this piece is about the card's own
  corner menu. Show it there.
- **The learner taps it; nawana does not auto-detect.** Don't imply the app silently
  catches mishearings on the card — the control is the learner's choice. (The background
  drop in say-it-again is a different, invisible thing; don't conflate them on a slide.)
- **The misheard sample must look like an STT slip, not a grammar error.** See Proof. A
  clean learner mistake under "You said" undercuts the whole message.
- **Mechanics stay internal.** "slips removed, grammar score rescaled, weekly assessment
  re-run, no rep logged" is how it works — say it as "the app cleans up after itself," never
  as a spec on a slide.
- **Numbers are illustrative.** Any count / score / date on the card is kit sample data,
  never a user result.
- **Keep the demo in English** (target default); Korean labels are the reader's language
  (native ≠ target). Don't fake a non-English target line.
- **Threads text** written fresh (conversational), not the IG caption pasted. Hook: that
  moment you read "You said…" and it's not what you said — and what you can do about it now.

## Success signal

Afterwards look at: **saves** on the carousel (the "ugh, that's happened to me" recognition
saves well) and comments/DMs from learners describing being misheard (demand + trust signal);
community series views; profile visits / installs attributed around the post. This feature's
real win is trust, which is slow — treat any comment reading "finally, this is fair" as the
signal, not a metric. No public stat from internal telemetry.

## Community series entry (for publisher, draft only)

- `id: e22` (pending lead confirm vs e20/e21), `cat: "practice"`, `slides: 6`
- ko: title ≈ "잘못 들림", tagline ≈ "내가 안 한 말은 '잘못 들림' 한 번으로 점수에서 빼요"
- en: title ≈ "Misheard", tagline ≈ "One tap takes a misquote out of your score"
- (Copywriter finalizes titles/taglines in copy.md; these are placeholders.)

## open questions

- **Kit pose.** Does the designer add a faithful `nw-review` pose for the ⋯ menu open + the
  card leaving the deck, or do we tell it via the `card` pose + a ⋯ sticker? Status says the
  designer *may* add one — decide before copy locks card 3/4's render.
- **Episode id.** Confirm this is e22 (e20 = accent-words, e21 = coach-suggestion, both in
  flight) before the series entry is drafted.
- **Show the "Play your recording" button?** The real card carries a play-recording button
  by "You said" — hearing your own recording is how you'd *verify* a mishearing, which
  reinforces the honesty angle. The kit `card` pose doesn't currently render it. Worth a
  faithful add to the pose if quick; not required. Flagging for the designer/lead.
