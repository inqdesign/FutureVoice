# Brief · series 05 · 단어장 (Words)

Strategist, 2026-10-13. Intent only; copywriter writes ko and en natively. Source: community e13
"단어장 · 통화에서 나온 단어가 알아서 모여요" (레벨별 단어 지도 · 뜻, 예문, 발음까지 · 오늘의 단어
카드 · 밀어서 나중에 다시 · outro) and e14 "표현" (통화에서 들은 표현이 모여요, the same card).
Keep e13's beats, animate them, and add what e13 never showed: where the words come from (your
call) and where they go (your next call). Carry-overs fixed: light theme, kit only, eyebrow
"nawana · NN / 07", ONE story, no em dash, Threads reply.

## One message

**단어장에 적어 둔 단어가 정작 말할 땐 안 나와요. 나와나는 통화에서 나온 단어가 알아서 모이고, 내
목소리로 듣고, 다음 통화에서 직접 써요. 말한 단어는 '썼어요'가 돼요.**

(en intent: the words come from your own call, you hear them in your own voice, and the next
call is where you actually use them. A word you said beats a word you marked "I know".)

## Who it's for

The learner with a notebook full of words they never say: Anki decks, highlighted lists. Can
build sentences, reaches for "very good" when "compelling" is in their notebook. Has done the
interview call.

## Why now

- Series 05, after Say it again: 03 was the sentences, 05 is the words, both out of the same
  talk. Community e13 is screenshots; this is the live successor.
- The loop it shows is the product's differentiator ("every talk becomes your own study
  material") at its smallest unit, and its last beat (the next call ticks the word) is the
  part users don't find: the chip row in the call.

## The story

The interview talk's book. Its Words chapter (kit sample): initiative · perspective · compelling
· prioritize (the fluent self's words at or above the learner's level, minus what the learner
said). **The hero word: "compelling"**, from the fluent self's "That's a compelling
perspective." (the line of piece 02). Next call = piece 01 card 08 ("They call me yesterday" /
"Yes! I got the job."), where the learner says it: e.g. "Yes! I got the job. They said my story
was compelling." (intent; copywriter may tune).

## Proof in the app (HEAD code)

- Words chapter of a talk book (`TalkCurriculum.pickupCandidates`): the fluent self's words at or
  above the level, ungraded words the fluent self came back to across turns, minus the learner's
  own words, up to `maxWords`.
- The notebook fills itself (`VocabStore.keepFromTalk`, at summary): exactly the set the chapter
  shows, skipping known/used/kept and anything removed by hand. Not counted as the learner's rep.
- Word card (`VocabularyView` / word card, `CardButtons`): headword, part of speech, numbered
  senses, examples, Keep · I know · ↑ · ↓; pronounce = the learner's OWN cloned voice, cached
  (`StudyDeckView.speak`, `PhraseAudioStore`). Expressions use the same card (e14).
- Daily words deck (`DailyWordsView` / `StudyDeckView`): blue card, tap to reveal the meaning,
  "Hear it" in your voice, filed by drag/tray into 10 min · Tomorrow · 3 days · Got it; folders
  are where things ARE (Soon · Tomorrow · Later), and long-press re-files.
- The call spends the notebook (`TalkGoalChips`): today's due studying items ride as chips above
  the transcript and tick (green) the moment the learner says one (`CarryoverDetector`, the same
  judge as the wrap-up). Tap a chip: "Use this in the call", one sense, one example.
- Used outranks known: saying it in a talk moves the word to the top state and out of the
  notebook schedule (`VocabStore.ingest`, record `.used`); "I know" is only a claim (plain check
  vs filled check). The B1 word map (`nw-words` cloud) greys a used/known word with a green tick.
- Widgets: Vocabulary widget on the home screen. Captions only (no kit).

## Outline · 7 cards (eyebrow "nawana · NN / 07")

**01 · Cover (still).** Problem: 단어장에 적어 놓고, 말할 땐 하나도 안 나와요. Answer, bold: 통화에서
모이고, 통화에서 써요. `nw-futureself` circle + chips (통화에서 모이고 · 내 목소리로 듣고 · 카드로
넘기고 · 다음 통화에서 쓰고 · 말하면 '썼어요').

**02 · 통화 한 번이면 단어가 모여요.** Say: the words your fluent self used, at your level, collect
in the book and the notebook by themselves. Screen: `nw-bookpage` open("words") on the interview
book: initiative · perspective · compelling · prioritize. Poster: the Words chapter. Kit gap 4.

**03 · 뜻, 예문, 내 목소리 발음.** The sound card. Say: tap a word for its card; you hear it in
your own voice. Screen: "compelling" word card: adjective, senses, the talk's line as example,
the speaker button pressed. **Sound: Audio W1** (clone says "compelling", then "That's a
compelling perspective."). Poster: the card. Kit gap 1.

**04 · 하루치 단어, 넘기면서.** Keep e13's "오늘의 단어 카드" + "밀어서 나중에 다시". Say: a few a
day: say it, reveal, file it into 10분 · 내일 · 3일 · 알아요. Screen: blue card "prioritize" →
reveal → dragged to 내일, folder count ticks; next card "compelling" → 내일 too (so it is due in
the next call). Silent. Kit gap 2.

**05 · 다음 통화에서 칩으로.** Say: the next call carries today's words as chips; say one and it
ticks. Screen: `nw-call` with goals [compelling · prioritize · felt prepared], piece 01 card 08's
opener, the learner's line with "compelling" → `tick(0)` green. Poster: ticked chip over the
line. (Tap-a-chip sheet "Use this in the call" optional, kit gap 3.)

**06 · 말한 단어는 '썼어요'.** Say: "I know" is your word for it; saying it in a call is proof, and
the word moves on. Screen: `nw-words` cloud, the sheet on "compelling" → its cloud word greys with
the green tick (used), the bookmark empties; one or two other words already checked. Poster:
cloud with checks. Copy keeps known vs used honest (see Facts).

**07 · Outro (unchanged).**

## Audio

- **W1 · founder's Cartesia clone:** "compelling." (pause ~0.6 s) "That's a compelling
  perspective." Relaxed pace. Card 03 only.
- No learner take needed (05's tick is visual). Optional: the learner line on 05 in the founder's
  voice, only if the founder wants sound there.

## Kit gaps (mkt-web)

1. No full word card: `nw-words` has only the peek sheet (headword, POS, first meaning) and no
   "compelling" entry. Needs the card (senses, example from the talk, pronounce button with a
   playing state, Keep · I know · ↑ · ↓). Capture `-capture wordcard` first.
2. No word deck: the blue study card with reveal, "Hear it", the four-way tray and folder chips
   for WORDS (e13 slides 04–05). `nw-review` has the sentence-card deck (same tray) and may be
   extendable; check against a `daily-words` capture.
3. `nw-call` chip tap sheet ("Use this in the call") not in the kit. Optional.
4. Book Words chapter sample includes "that" (known) in `nw-bookpage`, which reads odd; swap for
   a real level word. The cloud sample (`CLOUD`) is the B1 list with no story words: add
   compelling / prioritize / perspective / initiative so 06 lands on the story.
5. No "kept into the notebook" moment (book → notebook). Show it by the order of cards, don't
   invent an animation the app doesn't have.

## Channels

- IG carousel, 7 items (01 PNG, 02–06 MP4, 07 PNG).
- Threads REPLY under 04: opens on the dead notebook ("적어 둔 단어, 말할 땐 안 나오죠"), the loop
  in one line (call → card in your voice → next call → 썼어요), "소리 켜고 3번째 장". ≤ 500 chars.
- Community: replace e13 단어장 (and point e14 표현 at it, same card) or add new; founder's call.

## Facts that must stay true

- Words come from the FLUENT SELF's lines at or above the learner's level; the learner's own
  words are excluded. Don't say "내가 한 말에서 단어를 뽑아요".
- The notebook fills itself with exactly the book's word set; removed-by-hand words don't come
  back.
- The pronunciation is the learner's cloned voice. Not a native or tutor voice.
- Chips tick only when the word is said; used outranks known; "I know" is a claim.
- A word said in a COACHED (practice) call is not credited as used. Keep 05's call ordinary
  (no "Try saying" line on screen).
- Deck delays are 10 min · Tomorrow · 3 days · Got it. No "spaced repetition algorithm" claims
  beyond that.
- Numbers (B1 · 16 / 2113, folder counts) are sample data.

## Risks / copy traps

1. "단어를 외워요" framing: the point is using, not memorizing. Lead with "말할 때 나온다".
2. Known vs used: never say "알아요 누르면 끝"; the strongest state is saying it.
3. Overlap with piece 01 card 07 (book chapters) and card 05 (coach "Try using"): this piece's
   chip is the notebook's chip row, not coach mode. Don't show the coach line.

## Success signal

- Saves (a study-method post), Threads replies about word apps.
- Product: `words_kept_from_talk`, `word_known`, and the share of chip ticks per call a week
  after posting (PostHog, read-only).
