# Brief · series 03 · Say it again (다시 말하기)

Strategist, 2026-10-13. Intent only: the copywriter writes ko and en natively from this, nothing
below is final wording. Source: community e11 "다시 말하기 · 같은 대화를, 이번엔 제대로" (6 slides:
intro, prompter, answer, scores + retry, scene door, outro), turned into animated kit scenes.
Carry-overs from piece 01 and the shadowing brief are fixed and not re-argued: light theme, kit
screens only, Pixelify wordmark, eyebrow "nawana · NN / 08", cover = a problem in the learner's
words → the answer, ONE story (the interview talk of piece 01), AI tutor vs my own voice only as a
pointer back, no em dash, captions + Threads reply + Desktop export.

## One message

**통화가 끝나고 "아, 이렇게 말할걸" 싶을 때, 같은 대화를 처음부터 다시 해요. 내 차례엔 고친
문장을 말하고, 유창한 나는 그때 그 목소리 그대로 대답해요.**

(en intent: the same call, done again the right way. Your lines come up corrected, your fluent
self answers exactly as it did, in your voice. It's the conversation, not a list of fixes.)

## Who it's for

The learner who replays a conversation in bed: they got through the interview call (piece 01),
saw the corrections, and still feel they never actually SAID the right version. Can build a
sentence, stumbles; has done at least one talk. Not a beginner piece.

## Why now

- Series 03, right after shadowing (02 = one line after your fluent self). Say it again is the
  same act at the size of a whole call, and it is the only door that puts the learner back
  INSIDE the call. The thread reads as a progression: one line → the whole talk.
- Community e11 already has the right beats (cover, "방금 그 대화를 다시 해봐요", "읽으면 미래의
  내가 답해요", "문장마다 점수, 아쉬우면 다시", "장면으로도"). Keep them, animate them, and fix
  what e11 got wrong for today's app: its prompter showed only corrected lines; the app now
  runs EVERY turn, an uncorrected one under "Say your line".
- e11's lines are already the interview talk ("So, how did the interview go yesterday?",
  "Honestly, it went really well"), so continuity with piece 01 is free.

## The story (same talk as piece 01)

The call from piece 01 cards 03–05, done again. Learner turns as they come up on the prompter:
1. "Honestly, it **went** really well. I felt prepared." (corrected: go → went, note 지난 일이라 과거형이에요)
2. "The one about my weak points. I took the initiative and **told** a real story." (corrected:
   tell → told, same grammar point; piece 01 card 05 ended on "tell")
3. One UNCORRECTED turn, said as said, e.g. "Thanks. I was nervous, but it felt good." (intent:
   short, correct, natural; copywriter may adjust). Its header reads "Say your line".
Fluent-self answers between them, verbatim from piece 01 + shadowing piece: "Hey, it's you, a few
years from now. So, how did the interview go?" · "Nice, you sound relieved! Which question was
the hardest?" · "That's a compelling perspective. You clearly took the initiative and
prioritized what mattered." · a short closing question after turn 3 (e.g. "So when do they
tell you?"), which sets up piece 01 card 08 ("They call me yesterday").

## Proof in the app (HEAD code)

- Door: the talk book's cover, "Say it again / 다시 말하기" under Continue · Replay
  (`ConversationDetailView`, shown when the script has a spoken line). Also from a routine block
  (`SayItAgainPicker`, the last 14 days' talks, newest pre-selected) and on Watch books.
- Intro (`SayItAgainView`): "Do this talk again from the start, and say your part the corrected
  way. The answers play just as they did." + "N lines · M corrected" + Start.
- What they read (`SayItAgainScript.build`): every learner turn in order. The turn's own whole
  rewrite (`suggestion.alternative`), else the summary's fixes spliced into the line, else what
  they said. Header "Say it the fixed way" for a corrected line, "Say your line" otherwise;
  fixed words highlighted (`highlightedCorrection`); note under it. Misheard turns are dropped.
- The answers are the call's own audio (`TurnAudioStore`), never re-synthesized: the fluent
  self in the learner's cloned voice. While it plays: "<Future self> is answering" + Skip.
- No countdown: the mic opens with the line; a line nobody started WAITS; the take ends 1.5 s
  after they go quiet ("Moves on when you finish").
- Each read line gets a score (match, no rhythm), graded in the pause while the answer plays,
  and a Retry button for as long as the screen is open. Under 75
  (`PracticeStats.retryThreshold`) it shows what the mic heard ("Heard: …").
- Finish: "X of N lines read · A average", Run again, Done.
- A passing read of a CORRECTED line masters that fix in the book's Drill chapter (it carries
  `TalkCurriculum.correctionId`); uncorrected lines are scored and counted, not book items.

## Outline · 8 cards (eyebrow "nawana · NN / 08")

**01 · Cover (still PNG).** Problem, learner's words: 통화 끝나고 나서야 "아, 이렇게 말할걸"
해요. Answer, bold: 같은 대화를, 이번엔 제대로. Screen: like piece 01's cover, `nw-futureself`
in a circle + chip list of the beats (책에서 다시 말하기 · 내 차례엔 고친 문장 · 대답은 그때 그대로 ·
고칠 게 없던 말도 · 문장마다 점수 · 교재에 체크). No phone.

**02 · 통화 교재에서 '다시 말하기'.** Say: the call you just had, from the start, with you in it.
Screen: `nw-bookpage` cover ("How the interview went") → the 다시 말하기 button pressed →
`nw-sayagain` intro (Job interview, the intro line, "3문장 · 2개 교정됨", 시작). Poster: intro.
Kit: bookpage has the button but no press method; sayagain intro count is hard-coded 2/2.

**03 · 내 차례엔 고친 문장이 떠요.** Say: your line comes up corrected, what changed in blue and
why under it. Screen: opener row plays in, prompter card "고친 대로 말해 보세요" with "Honestly,
it **went** really well. I felt prepared." + 지난 일이라 과거형이에요. Silent (the reading is 04).
Poster: the prompter card.

**04 · 대답은 그때 그 목소리 그대로.** The heart and the audio card. Say: you read, it answers
exactly as it did in the call, in your own voice, and the conversation goes on. Screen: the
learner reads (red dot pulsing, waveform), the line joins the conversation, "미래의 나 대답 중",
the answer row "Nice, you sound relieved! Which question was the hardest?" lands, the score
appears in the pause (92). **Sound: Audio L1 then C1** (hand-off). "소리 켜고" hint like piece 01
card 02.

**05 · 고칠 게 없던 말도 내 차례.** The anti-misreading card: it's the whole conversation, not a
list of fixes. Say: lines you got right come up too, as you said them. Screen: turn 2 runs fast
(corrected, told), then turn 3 on the prompter under "내 말 해보세요"-style header (app: "Say your
line"), no highlight, no note. Poster: the uncorrected prompter over a feed of 4–5 rows.
Kit gap 2.

**06 · 문장마다 점수, 아쉬우면 다시.** Keep e11's title idea. Say: every line you read is scored;
a low one shows what the mic heard; Retry right there. Screen: turn 2 scored 61 with "들린 말:
… I took the initiative and tell a real story." (the old mistake slipping back, realistic) →
Retry tapped → 88, the heard line fades. Silent (optional: L2a then L2b audio).

**07 · 끝까지 하면, 교재에도 체크.** Say: the run ends with how many lines you read and the average;
the fixes you read well are checked off in the talk's book. Screen: finish panel "3문장 중
3문장 읽음 · 평균 N점" + 처음부터 다시 / 완료 → back on the book, Drill (드릴) chapter rows for
went / told turn green (kit gap 3). Poster: finish panel. Captions may add the two other doors
(the routine's 다시 말하기 block, Watch scenes) in one line; no card for them.

**08 · Outro (unchanged from piece 01).** nawana · 유창한 나에게 언어를 배우세요. · 첫 20분은
무료예요 · nawana.app.

## Audio (founder's clone takes from Cartesia; designer muxes)

- **L1 · learner, founder's own voice (reconfirm public use):** "Honestly, it went really well. I
  felt prepared." Read once, natural, slightly careful. Card 04.
- **C1 · founder's Cartesia clone:** "Nice, you sound relieved! Which question was the hardest?"
  Relaxed pace. Card 04, right after L1 with a natural ~0.5 s gap (the score lands in it).
- Optional (06): **L2a** learner "The one about my weak points. I took the initiative and tell a
  real story." and **L2b** the same with "told". Only if the founder wants sound on 06.
- Everything else silent. Reuse: none from piece 02 (different lines).

## Kit gaps (mkt-web, before design)

1. `nw-sayagain` STEPS are not piece 01's talk: turn 2 is "How relaxed I stayed, even on the hard
   questions" (fluent line "Nice! What surprised you most?"). Needs a `steps` input (or new
   sample) with the story above: opener, went, "Which question was the hardest?", told,
   compelling-perspective line, an uncorrected turn, closing question; intro count "3 · 2".
2. No "Say your line" state: the prompter header is always "고친 대로 말해 보세요"/"Say it the
   fixed way". Add the uncorrected header + no-highlight, no-note line (app: `isCorrected` false).
3. After the run, the book's Drill chapter can't show the fixes mastered (same gap as the
   shadowing brief's 3): needs a mastered row state + tab count.
4. No press/tap method for the bookpage cover's 다시 말하기 button; no retry-tap animation that
   re-scores a row in `nw-sayagain` (the Retry chip is drawn, not live).
5. During the read, the kit shows no "listening" signal beyond the static red dot; the app's
   footer waveform animates with mic level (`symbolEffect` variableColor). Nice to have.
6. Em dash in the kit's sample strings: check nothing with "—" is on screen (piece 01's sweep
   still applies).

## Channels

- **IG carousel**, 8 items (01 PNG, 02–07 MP4 8–15 s, 08 PNG), 1080×1350.
- **Threads: a REPLY in the series thread** under 02. No re-introduction of nawana. Opens on the
  moment (the call is over and the better sentence shows up too late), the answer in one line
  (the same call again, your part corrected, its answers as they were, in your voice), one line
  that it's the whole conversation, not a fix list, then "소리 켜고 4번째 장". May point back
  once ("지난번 그 면접 통화"). ≤ 500 chars, no hashtags, first 7 items.
- **Community:** e11 다시 말하기 exists (screenshots, prompter shows only corrected lines).
  Recommend replacing e11's slides with this set; founder's call, approval needed.

## Facts that must stay true (reviewer checks)

- It's the WHOLE talk: every learner turn comes up, corrected ones corrected, the rest as said.
  Never "고친 문장만 연습해요".
- The answers are the call's own recorded audio, unchanged. Not new lines, not a tutor voice.
- The learner reads; nothing tells them to "repeat after". No countdown, no timer.
- Score = how much of the line was said (match). No rhythm or pronunciation grade here. Don't
  write 발음 점수.
- Heard text shows only under 75. Retry stays available.
- Only a corrected line, read well, checks off the book's Drill item. Don't claim the whole book
  completes.
- It costs no talk time (nothing synthesized, `BillingGate` not used). True, but keep it off the
  cards; the only price line is "첫 20분은 무료예요". If the founder wants it, captions only.
- Watch scenes have the same door (you read the fluent self's side of the scene). Captions only.
- Numbers (92, 61, 88, average) are sample data.

## Risks / copy traps

1. "다시 말하기" next to "섀도잉" (02): keep them apart. Shadowing = follow one line after your
   fluent self; Say it again = you are back in the call, saying your own part. No "따라 말하기".
2. "내가 한 말을 고쳐서" is right for corrected lines; the uncorrected turn is "내가 한 말 그대로".
3. Whose voice: the answers are the fluent self (my clone); the reading is me. Don't call the
   learner's take "내 목소리로 듣는" anything.
4. The founder's own voice (L1) in public: reconfirm.
5. Continuity: piece 01 card 05's learner line ends "and tell a real story"; this piece's turn 2
   fix must be "told", same point (past tense) as turn 1. Good; don't introduce a new grammar
   point.

## Success signal

- IG saves and completion to card 04 (the sound card); Threads replies under the reply.
- Product (PostHog, read-only, a week after posting): `say_again_run` and `plan_say_again_start`
  per active learner vs the week before; share of talk books with a Say it again run.
