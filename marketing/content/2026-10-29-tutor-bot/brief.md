# Brief: 2026-10-29-tutor-bot

Founder asked for this piece directly on 2026-11-09. It failed on autopilot at 1.2.6 only
because no capture existed. Series: **나와나로 할 수 있는 것**, cat `talk`, a new entry.

## One message

**앱을 열면 튜터가 지금 할 일 하나를 골라 둬요.**

(EN intent, to be written natively: you open the app and your tutor has already picked the
one thing to do now.)

Founder's purpose for the feature: learners find the app difficult and feel there is too
much to do; the tutor is the one place where you never lose what to do next. A card that
doesn't answer "what do I do now?" is the wrong card.

## Who it's for

Someone a few days in, with ten minutes on the way home. They open nawana, see talk, review,
shadowing, say it again, a podcast, and close it because they can't decide where to start.
Honest floor as usual: someone who can already build a sentence, stumbling.

## Why now

- The founder asked for it, and the capture that blocked it now exists.
- The chat is the part people miss. Last 14 days, unique learners, test accounts filtered
  (one-off PostHog count, not a governed metric, small numbers): 60 saw the note, 15 started
  something from it, 14 tapped a pick, **11 opened the chat, 5 asked a question**. The face
  has no label. So the piece has to teach where the face is and that it can be asked.
  **Internal only. These numbers never appear in public material.**

## How it stays distinct

| Piece | What it owns | Words and screens to stay away from here |
|---|---|---|
| `2026-10-25-tutor-goal` | Tutor MODE: inside a call, the fluent self teaches 3–4 challenges | 수업, 과제, 체크리스트, the call screen, the in-call strip |
| `2026-11-07-tutor-reading-speech` | Text the tutor wrote, read aloud in Speech, scored | 소리 내 읽기, 프롬프터, 점수 |
| `2026-10-21-routine-your-way` | Building a routine in setup | The routine builder and the weekly grid |
| **This piece** | **Outside any call: the face on the Talk tab, in text, tells you what's next** | |

The one contact point with tutor mode is a button label on card 05. The screen it opens is
not shown.

## Proof in the app

Source: `CLAUDE.md` "The tutor bot is an AGENT", `TutorBot.swift`, `TutorAgent.swift`,
`TutorBotViews.swift`, `TutorTodayRows.swift`.

- **Face:** bottom right of the Talk tab (`TutorBotButton`). Tap opens the chat.
- **Note:** on the day's first open of the Talk tab. Greeting, routine summary, an optional
  one-line why, then 지금 / 다음 / "오늘 할 일 N개 더" folded (`TutorNoteCard`,
  `TutorTodayRows`). 나중에 and 물어보기 at the foot. Nothing is blocked; a tap outside folds it.
  It is computed in code from the routine, goals and logs (`TutorToday.ranked`), no model.
- **Bubble:** only when there is something to say: a step finished and the next is ready, a
  planned time arrived, the day is done. At most 3 a day, never the same one twice
  (`nextBubble`, `maxBubbles`).
- **Chat:** sheet titled 개인 튜터. Suggestion chips include 지금 뭐 하면 좋을까요?,
  왜 자꾸 같은 실수를 할까요?, 5분밖에 없어요. A model answers from the learner's own data, can look
  up a talk, the mistakes, the notebook and more (`TutorTools`), and adds 0 to 2 buttons,
  each of which only OPENS something (`TutorAction`).

## Outline: 6 cards

Template `marketing/templates/carousel.html`. Working lines below are intent and length
checks for the Korean, not copy; the English is written natively from the intent.

| # | Working title | What the card says | Screen state | Moves in on |
|---|---|---|---|---|
| 01 Cover | 오늘 뭐부터 할지,<br>튜터가 골라요 | Open the app and today is already sorted. | **S1** note, whole phone | Stays wide, works as a grid still |
| 02 | 지금 할 일 하나 | One thing now, with why, one next, the rest folded and one tap away. | **S1** | 지금 row and the why line |
| 03 | 끝나면 다음을<br>알려 줘요 | When a step is done it says what's next. Otherwise it stays quiet. | **S2** bubble | Bubble and the 시작 button |
| 04 | 5분밖에 없을 땐<br>물어봐요 | Tap the face at the bottom right and ask. It picks one thing and hands you the button to start. | **S3** chat, the 5-minute question | Answer and its button |
| 05 | 내 대화를 보고<br>답해요 | It answers from your own talks, quoting what you said, and offers the next step. | **S4** chat, the repeated mistake (optional **S5** beat first) | Quoted line and 튜터와 말해 보기 |
| 06 Outro | fixed | Wordmark · 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app | `nw-futureself`, no capture | None |

Card 05 is the differentiator: every talk becomes your own material, here as answers.
Sticker option on 05 only: none needed unless the quoted line is too small on the phone.

## Screens to capture (Korean and English each)

Korean and English readers get two full render sets (`renders/`, `renders-en/`), as
`2026-10-25-tutor-goal` did. The note is all chrome, so a mixed-language card doesn't work.

- **S1 Note.** Talk tab, note open, face above the tab bar. Reseed it (see below). The
  current `marketing/captures/tutor-bot-plan.png` can't be used.
  Need: routine of 3 things, roughly 25 to 30 minutes; a why line visible (`TutorCopy.why`:
  focus label with 2+ talks); 지금 = talk block, 다음 = review; fold reads 2 or 3; no goal row.
- **S2 Bubble.** `marketing/captures/tutor-bot-bubble.png` is good for Korean (복습 끝 → 섀도잉,
  시작 · 지금은 안 할래요). English still to capture: `-tutorShow bubble`.
- **S3 Chat, 5분밖에 없어요.** Learner's chip question, the answer picking ONE thing with its
  reason, one button that starts it.
- **S4 Chat, 왜 자꾸 같은 실수를 할까요?** Answer quoting the sample learner's own sentence, button
  튜터와 말해 보기 (`lesson` action).
- **S5 optional, Chat "looking" line.** The thinking row reading 자주 하는 실수를 살펴보고 있어요…
  (`TutorTools.progressLine`, `TutorAgent.swift`; drawn in `TutorChatView`). Only if a real run
  actually does the `mistakes` lookup; drop it otherwise.

Capture notes:
- `-tutorShow chat` opens the chat but seeds no thread. S3 and S4 need a seeded
  `tutor_chat.json` with those two exchanges scrolled into view (the view only scrolls on a
  new message).
- **The answers must be real model output.** Generate them with
  `scripts/tutor-agent-probe.py` on a fixture learner, or a live run on seeded talks. Don't
  type them by hand. Pick a run whose buttons are the ones above.
- Fixture data only. No real learner's lines, and not the founder's.
- No kit screen exists. Every card works as a still with the template's zoom, so stills in
  `nw-phone` are enough. A `nw-tutorbot` build would add the note rising and the fold, but
  nothing depends on it. Follow `marketing/FIDELITY.md` either way.

## Channels

- **Instagram carousel**, 6 items, 1080×1350. Hook on the moment, "오늘 뭐부터 하지?" in spirit.
  The caption must say where the face is. 3–5 hashtags.
- **Threads**: a reply in the ongoing series thread (`marketing/series.md`), opening on this
  problem, no re-introduction of nawana. Inviting replies with "뭐부터 해요?" fits.
- **Community series**: new entry, cat `talk`, same day. Goes live only with founder approval.
  No tutor-bot entry in `series.json` yet; the publisher picks the id.

## Risks and copy traps

1. **The tutor is not the fluent self.** Its prompt says so. It writes text, in polite 해요체,
   in no one's voice. Never "미래의 내가 골라 줘요" or "내 목소리로 알려줘요" on cards 01–05. The
   2026-10-25 piece says the fluent self becomes a teacher; that's the in-call mode. Avoid the
   phrase "AI 튜터" too, since BRAND uses it as the comparison.
2. **"하나" means the view, not the workload.** It shows now, next and a fold; everything is
   still one tap down. Don't say "하루에 하나만 해요" or that the study load shrinks.
3. **Timing.** The note comes on the day's first open of the Talk tab, not "매일 아침". The
   bubble appears only on the Talk tab while the app is open. It is not a notification and
   doesn't reach a closed phone.
4. **Who chooses.** The note's order is a fixed rule over the routine and goals. "튜터가 골라요"
   is fine (the app says so). "AI가 분석해서" is not. Only the chat is a model, so no "always
   right".
5. **Needs practice on file.** With no routine the note says so and suggests a talk and review.
   With no talks the chat has little to quote. Don't promise a day-one answer from "내 대화".
6. **Buttons are 0 to 2 and depend on the question.** Don't say every answer has one. They
   only open things, and that may be said.
7. **Capture traps.** The current plan capture reads "5가지, 70분" and "9개 더", which argues
   against the message. It has a debug "◀ Speech dev" link in the status bar, and a real airline
   as the sample goal (debug seed). Reseed, and capture on the current build.
8. **Costs and platforms.** No free or unlimited claim about the chat: the server has a
   200-a-day cap and this brief didn't verify pricing. Android has the tutor files; don't name
   a platform on the cards.
9. Sample numbers are illustrative. 해요체, no 당신, no em dashes. "첫 20분은 무료예요" gets
   rechecked on posting day.

## Open question

The goal row (D-12, reading as 지금) is real and strong, but it pulls the piece toward
`2026-11-07` and needs a learner with a goal. This brief leaves it out and leads with the
routine. If the founder wants it on the cover instead, S1 needs a generic goal, with no real
company name, and the count on the fold still has to stay small.

## Success signal

- Instagram: saves relative to reach, profile visits and link taps within 72 h.
- Threads: replies describing what people do first.
- Community: entry views.
- Internal only: unique learners on `tutor_bot_opened` and `tutor_bot_asked` for the 14 days
  after posting against the 11 and 5 above. The count is small, so read it as a direction.
