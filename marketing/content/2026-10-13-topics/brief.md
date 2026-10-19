# Brief · series 04 · 내가 원하는 토픽 (Talk: my own topics)

Strategist, 2026-10-13. Intent only; the copywriter writes ko and en natively. Source: community
e02 "전화 한 통" (ring = 오늘 말한 만큼 링이 채워져요 · "오늘 뉴스로 말을 걸어요" · 번갈아 말해요 ·
칩 · 교재) and e03 "통화 설정", plus the Talk home as it is at HEAD. Keep from e02 what is about
WHAT you talk about (the News slide, the tap-to-call); the call itself, corrections, chips and
the book are already pieces 01/05. Carry-overs fixed: light theme, kit only, eyebrow
"nawana · NN / 07", cover = learner's problem → answer, ONE story (the interview), no em dash,
Threads reply.

## One message

**교재 속 주제는 내 얘기가 아니라서 할 말이 없어요. 나와나는 내 면접 직무의 질문, 내가 챙겨 보는
소식, 내가 겪을 상황으로 통화해요.**

(en intent: talk about what's actually yours: your interview role's questions, this week's news
on what you follow, your own saved situation. One tap and the call starts on it.)

## Who it's for

Someone preparing for a real thing (the interview of piece 01) who has used apps where the topic
is "Describe your hometown". They have plenty to say about their own job hunt and the things they
follow, nothing to say about a textbook prompt. Sentence-builder, not a beginner.

## Why now, and how this differs from `2026-10-13-learning-purpose`

- Founder named this episode "내가 원하는 토픽". The Talk tab became a row of the learner's own
  chips with 1.1.8 (`feat/learning-purpose`), and the settings sheet behind the sliders icon now
  holds purposes + per-purpose details + interests in one place (`DiscoverSettingsSheet`).
- `learning-purpose` (autopilot, ready) owns "pick WHY in onboarding → the chips follow", with
  the ready-made StarterSituations lists. THIS piece is the next level down: the topics written
  for YOUR details (the role you're applying for), news on interests you typed (anything: a
  team, a person, a field), and your own saved situation. Don't reuse its cards or its list
  rows; don't post it next to that piece.

## Proof in the app (HEAD code)

- Talk home (`ConversationHome`): greeting, the "Let's talk" ring (free talk, one tap),
  "Tell me more about you", then the chip row + one list (`DiscoverSection`). Chips =
  `LearningPurposeStore.chips(level:)`: the learner's purpose chips in the order picked, then
  News, then Scenarios. Header tools on the row: sliders (settings) and refresh.
- Talk settings (`DiscoverSettingsSheet`, "Talk settings"): "Why are you learning?" (up to
  three), each with details, for interview "Role you're applying for — e.g. backend developer";
  "Interests" with a field "A company, a team, a person — anything", footer "The News chip
  brings this week's stories for each one."
- Interview chip: field topics written for the role (`PurposeTopicEngine`, eight at a time,
  refresh walks the pool then grows it, cached), loading row "Writing topics for your field…",
  empty-role row "Add the role you're applying for — I'll ask its questions"; the interview
  starters ("Tell me about yourself" · with an interviewer, …) under them.
- News chip: recent stories matched to interests (`NewsTopicEngine`), rows like "Did you see …?"
  with the category caption; tap → the call opens on that story.
- Scenarios chip: the learner's own situations, newest first ("Job interview · panel round ·
  with Interviewer"), "All scenarios" tail, "+" to build one. A scenario talk casts the model as
  that counterpart, and its chip row is filled from that scenario's book first
  (`TalkGoalPicker.pick(forScenario:)`), rotating per run.
- Every row tap = `BillingGate` then `ConversationView`. Everyday chip: ready-made situations,
  a check on ones already talked through.

## Outline · 7 cards (eyebrow "nawana · NN / 07")

**01 · Cover (still).** Problem: 교재 주제로는 할 말이 없어요 (내 얘기가 아니라서). Answer, bold:
내 얘기로 통화해요. `nw-futureself` circle + chips (내 면접 질문 · 내가 챙겨 보는 소식 · 내 상황 ·
탭 한 번에 통화). No phone.

**02 · 대화 탭 한 장에 내 주제가.** Say: open Talk and your topics are already there, in your
order; one tap starts the call. Screen: `nw-home` with the chip row as the learner's (Interview ·
News · Scenarios), slow scroll from the ring to the list, chips switch once. Poster: list visible
under the chip row. Kit gap 1.

**03 · 지원하는 직무만 적으면, 그 직무 질문으로.** The core card. Say: write the role once and the
Interview chip fills with that role's questions. Screen: Talk settings sheet, the role field
typed ("backend developer", sample), Save → the Interview chip shows "Writing topics for your
field…" → eight field topics land (sample titles in English, e.g. "Walk me through a system you
designed", "A bug you couldn't find for days" — the designer must take real output, see Risks
2). Poster: the filled list. Kit gaps 1–2.

**04 · 챙겨 보는 게 있으면, 이번 주 소식으로.** Say: add anything you follow and the News chip
brings this week's stories about it; tap one and your fluent self opens on it. Screen: interests
field gets a sample interest → News list refreshes (refresh icon spins) → tap "Did you see …?"
→ `nw-call` opens, fluent self says the opener. Poster: the call's first line. Kit gap 2.

**05 · 내 상황은 저장해 두고 몇 번이고.** Say: the interview situation you made is saved; tap it
again and the interviewer picks up, with that situation's own words as chips. Screen:
Scenarios chip → "Job interview · panel round · 상대: Interviewer" tapped → `nw-call` with the
interviewer's opener (a preset voice, NOT the clone), chips = the scenario book's words/
expressions (e.g. took the initiative · walk you through · prioritize). Poster: the call with
chips. One line points at Watch (later episode) only in captions.

**06 · 그냥 하고 싶은 얘기는 링 한 번.** Short closing beat: no topic needed, the ring starts a free
talk, and a free talk starts from your own day (piece 01's call). Screen: scroll back up,
`home.tapRing()` → call opens "Hey! How's your week been?" (piece 01 card 08's opener). Poster:
ring. Optional; cut to 6 cards if the copywriter finds 06 repeats piece 01.

**07 · Outro (unchanged).**

## Audio

None needed: the point is what's on the list. If the founder wants one sound, card 04's news
opener in the Cartesia clone (one sentence, the sample story's "Did you see …?"). Not required.

## Kit gaps (mkt-web)

1. `nw-home` chip labels are fixed to 뉴스 · 일상 · 상황 (News · Everyday · Scenarios). Needs a
   chips input (Interview · News · Scenarios) with per-chip lists and the tools that follow the
   chip. There is no simulator capture of the purpose-chip state yet (learning-purpose status
   says the same): capture `-capture` Talk with purposes set before building it.
2. No `DiscoverSettingsSheet` ("Talk settings": purposes, role field, Interests field) in the
   kit, and no capture. Without it, cards 03/04 lose their first half; fallback = start on the
   list already filled and say "직무를 적어 두면" in copy only. Do not draw the sheet from
   imagination.
3. No field-topic row style (person.crop.square icon, no caption) or the "Writing topics for
   your field…" loading row.
4. `nw-call` with a counterpart (the interviewer's name in the header, preset voice, scenario
   chips): check the kit can title the call with the scenario and show the counterpart label
   instead of "Future self".
5. News rows are kit samples (folding phone, beef tallow, laundry robot). Keep them neutral (no
   real company), or add a sample interest row set that matches the sample interest.

## Channels

- IG carousel, 7 items (01 PNG, 02–06 MP4, 07 PNG).
- Threads REPLY under 03: opens on "textbook topics give you nothing to say", answer in one line
  (your role's questions, the news you follow, your own situation), "탭 한 번이면 그 얘기로 전화가
  와요" in spirit. ≤ 500 chars, no hashtags, first 6 items.
- Community: no single old entry matches (e02 is the call, e03 settings). New entry, category
  talk, founder approval.

## Facts that must stay true

- Up to three purposes; chips follow the order picked, then News, then Scenarios.
- Field topics need the detail (role) written; eight shown at a time; refresh shows more.
- News = recent stories matched to interests, refreshed on tap; no promise of "real-time" or
  "today's headlines" for every interest.
- A scenario call talks with that counterpart in a preset voice; only the fluent self is the clone.
- Talking costs talk time (metered); "첫 20분은 무료예요" is the only price line.
- Topic titles are material (English on screen in both versions); chip labels and captions are
  chrome (ko on the ko version).

## Risks / copy traps

1. Overlap with `learning-purpose`: no "왜 배워요" onboarding picker on any card, no starter lists.
2. Field topics are model-written. Sample titles must be real output for the sample role (run the
   app with role "backend developer", take the eight it writes), never invented.
3. Real names in news or interests (companies, teams, people): avoid on screen; use a neutral
   interest (e.g. "AI / tech", "the job market").
4. "원하는 주제 아무거나" is an overclaim for the chips; the free-talk ring is what takes anything.

## Success signal

- Saves + profile visits; replies that name a topic ("내 직무도 되나요?") = landed.
- Product: share of new learners who open Talk settings / edit interests in week 1; calls started
  from the Interview / News chips vs the ring (PostHog, read-only).
