# Brief · series 07 · 위클리 리포트 (Your week)

Strategist, 2026-10-13. Intent only; copywriter writes ko and en natively. There is no community
episode yet; the source is the app's "Your week" deck (`WeekRecapSheet`) and the kit
(`nw-weekreport`, 10 cards + archive). Piece 01 v2 card 09 already animated it once (report cover
→ grammar card → last card → test), a head start. Carry-overs fixed: light theme, kit only,
eyebrow "nawana · NN / 08", ONE story, no em dash, Threads reply.

## One message

**열심히는 한 것 같은데 뭐가 늘었는지 모르겠을 때, 한 주가 끝나면 내 한 주를 돌려줘요. 실제로 써먹은
말, 새로 받은 표현, 그리고 자꾸 틀리는 문법을 내 문장으로 짚어 줘요.**

(en intent: at the end of each week, your week comes back as a short deck: what you actually used,
what your fluent self gave you, and the one grammar point that keeps slipping, shown in your own
sentences, with a plan.)

## Who it's for

The learner a week into the interview story who can't tell if they're improving; has seen
dashboards of streaks and minutes that say nothing about their English. Not a beginner.

## Why now / order

- Series 07, the last of the founder's community-to-video set. In the app the deck comes FIRST
  (it closes when the test opens, and its last card starts the test), and two test kinds
  (grammar, upgrade) are written from its coach. Posted after 06, it answers "where did the test
  questions come from?" Keep the founder's order; card 07 points back to 06. If the founder
  wants the app's order, swapping 06/07 needs no copy change beyond the back-pointers.
- Piece 01 closed on "it remembers"; this is the weekly version of the same promise.

## The story (the interview week)

Sample week (needs a kit sample, gap 1): talks "How the interview went", "Job interview · panel
round" (scenario), a news talk, "Good news" (piece 01 card 08's call). Used what you practiced:
compelling (piece 05's next call) and prioritize (a later talk). Not "took the initiative": it was
said in piece 01's COACHED call, which credits nothing, and 06's gap item still asks it. New from your fluent self: prioritize what matters, walk you
through, put me at ease. **Grammar that keeps slipping: past tense drops out of a story**, shown
on the learner's own lines from the series: "it go really well → it went", "tell a real story →
told", "They call me yesterday → called". Words to level up: e.g. "very happy" ×4 → thrilled
("I was very happy when they called." → "I was thrilled when they called."). Coach's plan, three
steps, the third "이번 주 테스트를 풀어 보세요. 틀렸던 문제가 다시 나와요."

## Proof in the app (HEAD code)

- `WeekRecap` / `WeekRecapSheet`: a story deck that closes with the weekly test's opening and
  slides up by itself ONCE (`RootTabView.offerWeekRecap`); afterwards it lives in the archive
  (Practice's "Your week" row → `WeekRecapArchiveView`, "New" on unopened weeks). The Review
  header's calendar icon carries a dot while unread.
- Cards in order (kit `PAGES`): cover (days of 7, streak, four summary lines) · talks (minutes,
  vs last week, list) · used what you practiced · practice (became yours, sentences got down,
  shadow takes + average, scenes) · new from your fluent self · where you got stuck (+ last test
  score, misses come back) · grammar that keeps slipping (rule, own lines struck → fixed, tip) ·
  words to level up (instead ×count → better, own line rewritten, note) · from your coach
  (headline, how you speak + a quote, This week's 3-step plan) · this week's test (+ "Tell me when
  next week's is ready" notice offer, "Start this week's test").
- Coaching prose is in the learner's native language; quoted lines and words stay English.
- The coach is one model read of the week, written once and saved in the report; grammar and
  upgrade test items come from it (`WeeklyTestEngine` grammar/upgrade).
- A quiet week gets a short deck (cover, a fallback coach, test), never a scold.
- The weekly notice is OFF by default; offered on the last card only.

## Outline · 8 cards (eyebrow "nawana · NN / 08")

**01 · Cover (still).** Problem: 열심히는 한 것 같은데, 뭐가 늘었는지 모르겠어요. Answer, bold: 한
주가 끝나면 내 한 주를 돌려줘요. `nw-futureself` circle + chips (한 주가 끝나면 · 써먹은 말 · 새로
받은 표현 · 자꾸 틀리는 문법 · 코치의 한마디 · 그리고 시험).

**02 · 한 주가 끝나면, 알아서 올라와요.** Screen: `nw-weekreport` cover: days light up one by one,
"N / 7일", streak line, the four summary lines. Poster: cover. (Flame allowed here: it is the
report's streak, not the test's.)

**03 · 실제로 써먹은 말.** Say: what you studied and then said in a real talk is counted, with the
sentence you said it in. Screen: next → talks card (brief) → used card (compelling, prioritize,
each with the learner's line). Poster: used card.

**04 · 유창한 내가 준 새 표현.** Say: phrases your fluent self used this week that you haven't said
yet; they wait in your expressions. Screen: fresh card (three phrases with their lines). Silent.

**05 · 자꾸 틀리는 문법, 내 문장으로.** The core card. Say: different sentences, the same slip, in
your own words, with one tip. Screen: grammar card: "이야기 중간에 과거형이 빠져요", three struck →
fixed pairs from the series (go→went, tell→told, call→called), tip; slow scroll. Poster: the card.

**06 · 코치의 한마디, 이번 주 할 일.** Say: one read of how you speak and three things for this
week. Screen: words-to-level-up card (very happy ×4 → thrilled) → coach card (headline, the quote,
the 3-step plan). Poster: coach card.

**07 · 마지막 장은 이번 주 테스트.** Say: the last card opens this week's test, and its grammar
question is this week's slip (pointer to 06). Screen: test card, "다음 주 돌아보기도 알려 주세요"
tapped → "다음 돌아보기는 …에 도착해요", then "이번 주 테스트 풀기" → `nw-weeklytest` grammar item
("I took the initiative and tell a real story." → rebuild with told). Poster: test card.

**08 · Outro (unchanged).**

## Audio

None. The deck is read, not heard. (Nothing here proves a point by sound.)

## Kit gaps (mkt-web)

1. `nw-weekreport` WEEK sample is the Berlin-move week (flat, landlord, boxes, exhausted, decent).
   Needs an interview-week sample (or a `week` input) with the lines above, in both the English
   material and the Korean coaching (`COACH_KO`).
2. `nw-weeklytest` grammar item sample is "I end up carrying…" (the move story); card 07's hand-off
   needs the told item.
3. No transition from the deck's "Start this week's test" into the test sheet (designer can cut).
4. Week dates in the kit ("10월 3일 – 10월 9일", "10월 17일 (토)") should be re-set to the story's
   week; dates must be plausible, not today's real calendar claims.

## Channels

- IG carousel, 8 items. Threads REPLY under 06: opens on "늘고 있는지 모르겠다", the answer in one
  line (your week comes back: what you used, what's new, the slip that keeps coming back, in your
  own sentences), "지난 글의 시험 문제가 여기서 나와요". ≤ 500 chars.
- Community: new entry (category progress), founder approval. Since 05–07 close the founder's
  set, propose to the lead a closing Threads reply listing the seven episodes.

## Facts that must stay true

- The deck appears by itself once per week, when the test opens; afterwards in the archive.
- Grammar points and better words come from the learner's own lines that week; quotes must be
  theirs (in the story, lines the learner said in pieces 01/03).
- Coaching text is in the learner's language; material stays English.
- The weekly notice is off by default; never claim "알림이 와요" without "켜 두면".
- It's not a level/CEFR report (that's Progress). Don't say "레벨이 올라요".
- Numbers (5 / 7 days, 42 min, ×4) are sample data.

## Risks / copy traps

1. Streak framing: the report shows a streak; don't make the piece about streaks (routine is a
   later episode). One line at most.
2. "AI 코치가 다 분석해요": keep it to what the card shows (one read of the week, a plan).
3. Report vs test confusion: 07 is "what happened and what to work on", 06 is "check it stuck".
   Titles must make that split obvious.

## Success signal

- Saves; replies asking for the "how you speak" read on their own week.
- Product: `week_recap_opened`, `week_recap_action`, and `week_recap_reminder` opt-ins, before vs
  after (PostHog, read-only).
