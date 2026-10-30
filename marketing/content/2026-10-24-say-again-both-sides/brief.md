# Brief · Say it again — both sides (1.2.3 what's-new)

Strategist, 2026-10-24. Autopilot upload run, no founder input; request fixed by `status.md`.
Intent only — the copywriter writes ko and en natively from this, nothing below is final wording.
This EXTENDS series 03 "다시 말하기" (community e11, and the `2026-10-13-say-it-again` piece). Do NOT
re-introduce the whole feature from scratch: Say it again — putting the learner back INSIDE a past
call to re-say it corrected — is established. This piece tells what 1.2.3 added to it. Carry-overs
are fixed and not re-argued: light theme, kit screens only, pixel wordmark, eyebrow, ONE story (the
interview talk from piece 01 → 03), AI tutor vs my own voice only as a pointer, no em dash, captions
+ Threads reply.

## One message

**이제 '다시 말하기'에서 내 대사만 할지, 양쪽 대사를 다 할지 고를 수 있어요. '양쪽 대사'를 켜면 그 대화 전체를
혼자 다시 해요 — 내 말도, 유창한 내 대답도 내가 읽고요. 지금 어느 쪽을 읽는지는 항상 보여요.**

(en intent: now you choose — say just your lines, or both sides. Turn on Both sides and you run the
whole conversation yourself: your lines and your fluent self's answers, all read out loud by you.
It always shows which part you're on. Secondary beat: the red dot by the prompter now lights up with
your voice, so you can see the mic is hearing you.)

## Who it's for

The learner who already uses Say it again and wants more of the call in their own mouth. In "My
lines" (the default, series 03) the answers played back to them; now they can take both roles and
carry the whole conversation alone — no waiting, every line theirs to say. Can build a sentence,
stumbles; has done at least one talk and at least one Say it again run. Not a beginner piece.

## Why now

- 1.2.3 (build 119) ships it. Two founder/learner asks landed together: "both sides" was a learner
  request (2026-10-18, now out of a menu), and the founder moved it to a visible toggle on 2026-10-23
  because the old person-icon-behind-a-menu was unclear and took two taps.
- Series 03 already exists (e11), so the thread has somewhere to attach. This is a follow-up IN that
  thread, not a new episode: "다시 말하기, 이제 양쪽 다."
- The red dot fix (2026-10-23) is a small but honest "it's listening to you" beat that pairs with the
  reading screen the carousel already shows.

## The story (same talk as series 01 → 03)

The interview talk, run again. Reuse the kit's `INTERVIEW` sample (went · told · one uncorrected line,
`sayagain.js`). In "My lines": your turns come up corrected, the fluent self answers verbatim from its
own audio. In "Both sides": every line is yours to read in order, the fluent-self lines included
("Nice, you sound relieved! Which question was the hardest?", "So when do they tell you?"), and nothing
plays. The prompter header names whose line it is each time.

## Proof in the app (HEAD code — `SayItAgainView.swift`, `SayItAgainScript.swift`)

- **The toggle** is a segmented Picker pinned to the TOP of the run (`.safeAreaInset(.top)`), always on
  screen, one tap to switch: **My lines** (`bothSides = false`, the default) · **Both sides**
  (`bothSides = true`). ko labels: 내 대사 · 양쪽 대사.
- **My lines** = series 03 exactly: your turns on the prompter (corrected or as said), the fluent self's
  lines PLAY from the call's own recorded audio (`TurnAudioStore`, in your cloned voice, never
  re-synthesized).
- **Both sides** (`SayItAgainScript.bothSides`) = every line becomes yours to read, in order, the other
  side's included, and **nothing plays** — no "… is answering" phase. For a TALK, a fluent-self line you
  read is filed under its own turn id, so a passing read counts toward the book's **Shadow chapter**
  exactly like a shadow take. For a Watch SCENE, the counterpart's lines are practice only (not book
  material). Switching mode mid-run rebuilds the script under you from the start.
- **You always see which part you're reading** — the prompter header (`prompterPanel`): "Say your line"
  (uncorrected), "Say it the fixed way" (corrected, fixed words in blue + note under), or
  **"Say <Future self>'s line"** for an other-side line (`promptStep.isOtherSide`, `source.otherName`).
- **The red dot hears you** (2026-10-23): the `circle.fill` dot before that header is the mic — dim while
  the room is quiet (opacity 0.3), and it brightens and swells with the learner's voice level
  (`live.level`, up to full opacity and +60% size). It used to pulse on a timer and said nothing.
- Unchanged from series 03 and still true here: no countdown; the mic opens with the line; a line nobody
  started waits; the take ends when you go quiet; each read line is scored (match, no rhythm) with a
  Retry button; under 75 it shows what the mic heard. Intro line differs by mode (`bothSides` branch in
  the cover copy). Door, finish panel, Watch-scene version: all as series 03.

## Outline · 6 cards (eyebrow "nawana · NN / 06", cat practice)

**01 · Cover (still PNG).** What's new, not the whole feature. Hook in the learner's words: 통화를 다시
할 때, 이번엔 전부 내가. Answer, bold: '다시 말하기'에 양쪽 대사가 생겼어요. Screen: `nw-sayagain`
cropped to the top segment (내 대사 | 양쪽 대사) sitting over a hint of the conversation, or the segment
as a sticker over `nw-futureself` in a circle. Works as a grid still. No motion.

**02 · 내 대사만, 아니면 양쪽 다.** Say: the mode is now right at the top of the run, always visible,
one tap. My lines = the way it was (your part corrected, the answer plays). Screen: the run in **My
lines** — segment at top, your corrected line on the prompter ("Honestly, it **went** really well…"),
the fluent-self answer playing in. Poster: the segment + prompter.

**03 · '양쪽 대사'를 켜면, 대화 전체를 혼자.** The heart. Say: turn on Both sides and every line is yours
to read, your fluent self's answers included — you say them, nothing plays. Screen: tap **Both sides**,
the script rebuilds, a fluent-self line comes up on the prompter under **"미래의 나 대사를 말해 보세요"**
(app: "Say Future self's line"), the learner reads it, it joins the conversation. Poster: the other-side
prompter. Mark where a sticker of the segment (switched to 양쪽 대사) helps.

**04 · 지금 어느 쪽인지 항상 보여요.** Say: the line above the prompter always names the part — 내 말,
고친 대로, 또는 미래의 나 대사. So reading both roles never gets confusing. Screen: a short beat cycling
the three headers over their lines (your line → the fixed way → Future self's line). Caption may add, in
ONE line, that reading the fluent self's line on a talk counts toward the book's shadowing; no card claim.
Poster: the prompter header close-up.

**05 · 빨간 점이 내 말을 들어요.** The supporting beat. Say: the red dot by the prompter is the mic —
dim when it's quiet, bright and bigger when you speak, so you know it's hearing you. Screen: the reading
card, dot dim → the learner speaks → dot lit and swelling with the waveform footer moving. **Sound
optional** (a short learner read; see Audio). Poster: the lit dot + line.

**06 · Outro (unchanged).** nawana · 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app.

## Channels

- **IG carousel**, 6 items (01 PNG, 02–05 MP4 8–12 s, 06 PNG), 1080×1350. Default shape.
- **Threads: a REPLY in the series 03 thread** (under the 다시 말하기 post), not a new post and no
  re-introduction of nawana. Opens on the update (다시 말하기에 '양쪽 대사'가 생겼어요), one line on what
  it does (대화 전체를 혼자, 내 대답까지 내가 읽어요), one line that you always see whose 대사인지, then
  point to the sound card for the dot. ≤ 500 chars, no hashtags, first 4–5 items.
- **Community:** this is an extension of e11, not a new episode. Recommend updating e11's slides (or
  appending these as a short follow-up) rather than minting a new id. Founder's call; approval needed to
  change the live site.

## Kit gaps (mkt-web, before design — `web/kit/screens/sayagain.js`)

The kit predates 1.2.3 and has NONE of this piece's new surfaces. Needed:
1. **The top segment** `내 대사 | 양쪽 대사` (`My lines | Both sides`) — a segmented control pinned above
   the conversation, with a method to switch it (and animate the switch for card 02→03).
2. **Both-sides run** — a mode where fluent-self lines become prompter lines the learner reads (no
   "… is answering" phase), driven off the existing `INTERVIEW` sample.
3. **"Say <name>'s line" header** — the prompter header's other-side state (`isOtherSide`),
   `source.otherName` = 미래의 나 / Future self.
4. **Voice-reactive dot** — the header dot must dim/brighten/scale with a drivable "mic level", not the
   current timer pulse (`@keyframes pulse`). Needs a level input for the card 05 animation.
5. Em dash sweep on any new sample strings (the kit's house rule).

## Facts that must stay true (reviewer checks)

- **Both sides = you read every line, both roles, and NOTHING plays.** Never say the answers still play
  in Both sides; in that mode you say them. In My lines the answers play (recorded audio, cloned voice).
- **My lines is the default.** Say it again still works exactly as series 03 showed; this ADDS a choice.
- The toggle is always visible at the top, one tap. Don't describe a menu or a settings screen.
- The header always names the part (your line / the fixed way / their line). That's the "always see which
  part" claim — don't overstate it as a tutorial.
- The red dot is a MIC indicator (is it hearing me), not a score and not a recording light with meaning.
  Don't imply it grades or that brighter = better.
- Reading a fluent-self line on a TALK counts toward the book's Shadow chapter; a SCENE's counterpart
  lines are practice only. Don't claim it finishes the book. Keep this to captions.
- It's still the WHOLE conversation, not a list of fixes. Score = match, no rhythm/pronunciation grade.
  Heard text only under 75. Numbers are sample data.
- Costs no talk time (nothing metered). Keep it off the cards; only price line is "첫 20분은 무료예요".
- Don't call Both sides "shadowing" or "따라 말하기" — you read the conversation, you're not repeating
  after a voice. (It overlaps shadowing only in that reading the fluent-self line credits that chapter.)

## Risks / copy traps

1. The overlap with shadowing (series 03 card / e12): keep them apart. Shadowing = follow one line after
   your fluent self; Both sides = you carry the whole talk, both parts, from the prompter.
2. "양쪽 대사" must not read as "the app says both sides" — it's YOU saying both sides.
3. Whose voice: in My lines the answers are the fluent self (my clone); in Both sides there's no playback
   at all. Don't attribute a voice to the learner's own take.
4. The founder's own voice in any optional audio (card 05): reconfirm before public use, as series 03 did.
5. Continuity with series 01 → 03: same interview talk, same went/told past-tense point. Don't introduce a
   new grammar point or new lines.

## Success signal

- IG saves and completion to card 03 (the Both sides reveal); Threads replies under the series 03 reply.
- Product (PostHog, read-only, a week after posting): `say_again_run` with `both=1` as a share of all
  runs (the run logs the flag), and `say_again_run` volume per active learner vs the week before.
