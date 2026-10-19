# Brief · series 02 · Shadowing (섀도잉)

Strategist, 2026-10-13. Intent only: the copywriter writes ko and en natively from this, and
nothing below is final wording. Carry-overs from piece 01 (`status.md` of this folder) are
fixed and not re-argued: light theme, kit screens only, Pixelify wordmark, eyebrow
"nawana · NN / 08", cover = a problem in the learner's words → the answer, ONE story, AI
tutor vs my own voice, no em dash, 입이 안 떨어져요, captions + Threads + Desktop export.

## One message

**섀도잉도 유창한 내 목소리를 따라 해요. 남의 억양을 흉내 내는 게 아니라, 몇 년 뒤의 내가
내 통화에서 한 말을 따라 하니까 "어, 이건 나도 되겠는데?"가 돼요.**

(en intent: shadow a line your fluent self said, in your voice, from your own call. The target
is you, a few years on, so it's a goal you can reach, not an accent you have to act out.)

## Who it's for

The learner who already tried shadowing: a YouTube clip, a drama line, an AI tutor's audio.
They did it for a week, felt like they were doing an impression of somebody, and stopped.
Now they can build a sentence, they stumble saying it, and they're on the series thread
because piece 01 ("머리론 아는데 입이 안 떨어져요") hit home. Not absolute beginners: the
line on screen is a full 9-word sentence they've already heard in their own call.

## Why now

- Series order: piece 01 (core) ended on "소리 내어 내 것으로" and showed the shadow screen
  for ~3 s (card 07). The founder chose Shadowing as 02, so this is the zoom-in on that beat.
- Piece 01 card 02 planted the exact argument this piece cashes in: "AI 튜터의 목소리는 닿을
  수 없는 목표 같아요 / 내 목소리로 들으면 어, 나도 되겠는데?". Shadowing is where that
  sentence becomes a practice, not a feeling.
- The community archive already has e12 섀도잉 (old screenshot series, tagline "유창한 내
  목소리를 따라 말해요"). This piece is its live-kit successor, not a repeat: it adds the
  story (your own call), the duet and the book credit.

## The story (one talk, one line)

The same interview talk as piece 01 (kit sample book "How the interview went"). After the
learner said "I took the initiative and tell a real story", the fluent self answered:
"That's a compelling perspective. You clearly took the initiative and prioritized what
mattered."

**The line to shadow: "You clearly took the initiative and prioritized what mattered."**
Why this one: it is ONE sentence (the app splits a turn into sentences for the Shadow chapter,
see Risks 1), 9 words, short enough that the duet stays honest, it carries piece 01's
expression "took the initiative", and it is the fluent self saying something about YOU, in
your voice. "prioritized" (the -ed and the stress) is the natural place for a learner's take
to drift, which gives the result card and the loop card something real to show.

## Proof in the app (all HEAD code)

- The target is always the learner's cloned voice. `ShadowDrillView.loadAudio`: the call's
  own turn audio (`TurnAudioStore`) when the line is a whole turn, otherwise the phrase cache,
  otherwise one synthesis in `appState.voiceCloneId` with word timestamps (`purpose: "shadow"`).
  Never a preset or tutor voice.
- Where lines come from: `TalkCurriculum.shadowPicks`. Fluent-self sentences of 4–28 words,
  opener and farewell skipped, ranked by phrases the fluent self offered and words at or above
  the learner's level, up to 4 per talk. Book page ribbon "섀도잉" (`ConversationDetailView`),
  footer "이 대화에서 유창해진 내가 한 말을 따라 말해 보세요."
- Karaoke: words light as the target plays (`ShadowTimelinePlayer`, kit `_karaoke`).
- The take: 3·2·1, mic red, auto-stop after 1.5 s of quiet. The words are read from the audio
  (`ShadowTranscriber`, the target sentence is never shown to it), timings come from the device.
- The result: "이번 시도" score (`overallScore` = match, plus rhythm when measured), "일치도"
  (the target coloured by what was missed or said differently), "들린 내용" (the take's own
  transcript), "원본 / 나 / 말하기 속도" cells, beat dots under each target
  word (centre = on the beat, right = late, left = early; only on measured words,
  `WordTiming.isMeasured`), rhythm score with a metronome in the target header.
- Loop: tap two words to pick a phrase, loop it, speeds 0.5× · 0.75× · 1× · 1.25×
  (`TLConst.speeds`).
- "겹쳐 듣기 / Both at once": target at 0.4 volume panned left, the take at full volume panned
  right, both trimmed to their own first word (`playTogether`, `AudioLoudness.firstVoiceOnset`).
  App note: "원본 위에 내 녹음을 겹쳐서, 둘 다 첫 단어에서 시작해요. 어디서부터 밀리는지 들어보세요."
- It counts: a whole-line take at or above 80 (`ScenarioCurriculum.shadowMasteryScore`) masters
  that line in the book's Shadow chapter; the book's progress moves (`TalkCurriculum.build`).
  A phrase take never masters the line (`isPartial`).

## Outline · 8 cards (eyebrow "nawana · NN / 08")

**01 · Cover (still, works in the grid).** Problem in the learner's words: 섀도잉, 남의 목소리
따라 하면 연기하는 것 같아요 (founder's own reaction from piece 01: "따라 하면 연기하는 것 같아.
나 같지가 않아"). Answer, bold: 유창한 내 목소리를 따라 해요. Screen: like piece 01's cover,
`nw-futureself` speaking in a circle + the six beats as chips (내 통화에서 한 줄 · 내 목소리로
듣고 · 따라 말하고 · 박자까지 보고 · 겹쳐 듣고 · 교재에 체크). No phone.

**02 · 따라 할 문장은 내 통화에서.** Say: the lines come from what the fluent self said back in
YOUR talk, picked for your level, up to four a talk. Screen: `nw-review` shelf → the interview
book lands → `nw-bookpage` `open("shadow")` → two rows (see kit gap 2) → `tapLine(1)` on
"You clearly took the initiative…". Poster: the Shadow chapter with the row pressed.

**03 · 내 목소리로 먼저 들어요.** The heart of the piece. Say: the target sounds like you,
already fluent, so the gap you hear is one you can close (tie back, lightly, to piece 01 card
02; don't repeat the comparison). Screen: `nw-shadow` slides up, target plays, karaoke runs
word by word, playhead on the track. **Sound: Audio A.** No sticker: the comparison lives in piece 01 card 02, and the caption
points there.

**04 · 따라 말하면, 들린 그대로.** Say: 3·2·1, you say it, and the screen shows what the mic
actually heard and a score. Screen: countdown → take (mic red, karaoke on the learner's
clock) → "…" → result: score (sample, e.g. 72); under 일치도 the TARGET line coloured by the
diff ("prioritized" marked as said differently); under 들린 내용 the take as heard ("You
clearly took the initiative and prioritize what matter"). **Sound: Audio B** (the learner's take). Poster: result with the miss.

**05 · 박자까지 봐요, 어려운 데만 천천히.** Say: a dot under each word shows if you came in
on time; tap the hard words and loop them slower. Screen: result held, dots fade in (one or
two late dots on "prioritized what mattered"), metronome score in the header, then tap
"prioritized" and "mattered" → loop on → 0.5× → the phrase plays twice. Silent. Sticker: one
dot enlarged with "가운데 = 딱 맞게 · 오른쪽 = 늦게" if the card needs it (kit dot, not drawn).

**06 · 겹쳐 들으면 어디서 밀리는지 들려요.** The proof only this app has: the two voices are
the same timbre, so you hear yourself and your fluent self as one speaker drifting apart and
back. Screen: tap "겹쳐 듣기", playing state (see kit gap 5), the note under it. **Sound:
Audio C.** "소리 켜고 들어 보세요" hint, as on piece 01 card 02.

**07 · 80점 넘으면 교재에 체크.** Say: pass the line and it's checked off in the talk's book;
the book moves toward done. Screen: retake → 86 → close → back on the Shadow chapter, the row
turns to the green check, ribbon count and the cover's progress tick up (kit gap 3). Poster:
the checked row.

**08 · Outro (unchanged from piece 01).** Wordmark · 유창한 나에게 언어를 배우세요. · 첫 20분은
무료예요 · nawana.app.

Optional, only if the founder wants a 9th: "다시 말하기" as a one-card pointer (the whole talk
said again, prompter) is a DIFFERENT feature and its own later piece; I'd leave it out.

## Audio (founder makes the takes; designer muxes)

- **A · target, founder's Cartesia clone:** "You clearly took the initiative and prioritized
  what mattered." One clean take at the app's default pace (Relaxed, 0.9) if Cartesia's speed
  control allows; keep the word timestamps (karaoke + dot positions are measured from them).
  Used on 03, again inside 06.
- **B · the learner's take, founder's own voice** reading the same line once, honestly (a
  slightly late or clipped "prioritized" is the point, don't polish it). The founder OK'd his
  own voice in public for piece 01; confirm again for this piece. If not, a team member's
  Korean-accented read, never a preset voice. Used on 04 and 06.
- **C · duet:** B at 1.0 panned +0.35, A at 0.4 panned −0.35, each trimmed to its first voiced
  frame (the app's rule), mixed with ffmpeg. Used on 06. A + C is the reason to turn sound on.
- 05 and 07 silent (07 may replay the last second of the 86 take, optional).

## Kit gaps (mkt-web, before design)

1. `nw-shadow` has no `line` input: LINE (text, times, dev), the 96 score, the 15/18 + 88
   header, the 5.7s/6.5s/1.13x cells and the diff/heard text are hard-coded. Needed: a line
   object (text, word times from Audio A, deviations, score, heard text, pace) and a second
   result (72 then 86).
2. Book Shadow chapter shows "That's a compelling perspective. You clearly…" as ONE row; the app
   splits a turn into sentences, so it is two rows. Fix the sample (and the chapter count 0/2).
3. After a passing take the Shadow row and ribbon still read unmastered (noted in piece 01
   status). Needs a mastered state for the row + count + cover progress.
4. During the take the mic sits below the visible window; recording reads only by the
   countdown and karaoke. Pan or reposition so the red mic is on screen.
5. "겹쳐 듣기" is a static button: needs a pressed/playing state.
6. Em dash in the kit's en `bothNote` ("…first word — hear where you drift") and the Words
   footer; the carousel sweep handles it, but fix at source.
7. `match`/`heard` are swapped in the kit. App (`ShadowDrillView.diffSection`): under "Your
   match / 일치도" the TARGET line coloured by the diff; under "What I heard / 들린 내용" the
   transcript of the take. Kit shows the lower-cased line under 일치도 and the target under
   들린 내용.

## Channels

- **IG carousel**, 8 items (01 PNG, 02–07 MP4 8–15 s, 08 PNG), 1080×1350.
- **Threads: a REPLY in the series thread** under piece 01. No re-introduction of nawana, no
  "voice clone" explainer. Opens on the problem (shadowing someone else's voice feels like
  acting, so it doesn't last), then the answer in one line (a line your fluent self said in
  your call, in your voice), then the three things it does (what the mic heard, the beat,
  both at once), then "소리 켜고 6번째 장". May point back once ("지난 글의 그 면접 통화").
  ≤ 500 chars, no hashtags, first 7–8 items.
- **Community:** the archive already holds e12 섀도잉 (old screenshots). Founder decides: replace
  e12's slides with this set (my recommendation, same title, same feature) or add a new entry
  as piece 01 did. Approval needed either way.

## Facts that must stay true (reviewer checks)

- The target is the learner's own cloned voice, always. Never "a native speaker's line".
- The line is the FLUENT SELF's, from the learner's own talk; the learner didn't say it.
  "내 통화에서 나온 문장" is right, "내가 한 말" is wrong.
- Up to 4 shadow lines per talk; the opener and farewell are skipped.
- Score = how much of the line was said (match) plus timing when measured. It is not a
  phoneme-level pronunciation grade. Don't write "발음을 분석해요" or "원어민 발음 점수".
- Beat dots appear only on words with measured timing; say "단어마다 박자", never "억양".
- Pass bar 80 masters the line. A phrase loop never checks the line off.
- Speeds are 0.5× to 1.25×. Duet: speeds are NOT matched, both start on the first word.
- Numbers on screen (72, 86, dots) are sample data, never results.
- Don't say shadowing is free or unlimited (a split sentence can be synthesized once, metered).
  "첫 20분은 무료예요" is the only price line. No trial.
- Not for absolute beginners. No promise of a native accent; the clone keeps the learner's
  timbre, and accent claims are out of scope.

## Risks / copy traps

1. **Sentence split.** If copy or kit shows the two-sentence turn as one shadow line, it
   contradicts the app. Use the one sentence everywhere.
2. **"내 목소리" vs "내가 한 말".** The voice is mine, the words are the fluent self's.
3. **AI tutor comparison** stays respectful and is a pointer back to piece 01, not a new
   versus card (BRAND: don't belittle tutors or natives).
4. **"연기 같아요"** is the learner's feeling about copying a stranger, not a claim about other
   apps. Keep it first-person.
5. **Say it again** is a different feature (whole talk on a prompter); don't blend its
   prompter into this piece's screens or copy.
6. The founder's voice (Audio B) in public: reconfirm.

## Success signal

- IG saves and shares on the carousel (a technique post should save better than piece 01).
- Completion to card 06 (the audio card) and replies on the Threads reply ("겹쳐 듣기 신기하다"
  type comments = the point landed).
- Profile visits from the thread vs piece 01.
- Product side (PostHog, read-only, after a week): new installs whose first 7 days include a
  shadow take (`shadow_transcript` events) vs the week before.
