# 튜터가 써 준 글, 소리 내 읽어요 — copy (tutor readings as speeches, 6 cards)

Autopilot run for 1.3.2 (134). The one message: **면접 준비로 읽던 글, 오늘의 뉴스 기사 — 튜터가 나를
위해 써 준 글을 이제 소리 내 읽고 점수를 받아요.** Every card traces to it. Each card was written in Korean
first and then separately in English, not translated. Script text + UI lines on screen stay English (the
kit's own sample + the designer's two custom scripts); every label and description around them is 해요체.
Never "당신". No "—" anywhere (middot "·" is fine, the app uses it).

This is the SOLO, private reading-aloud piece. There is NO board, NO ranking, NO competition in it — the
speech CHALLENGE leaderboard is a different feature and a different carousel (`2026-10-12-speech-challenges`).
Don't let a word of leaderboard copy leak in (brief risk 6).

Length target (matching the approved sibling pieces): ko descriptions ~40–58 characters, en ~90–140
characters, 2 lines on the render. Titles 2 lines, ~8–10 characters a line.

**For the designer (screens + beats per brief):**
- Eyebrow number → `NN / 06` (01 / 06 … 06 / 06).
- **Two custom scripts to write** (both in the target language, English by default), each believable as a
  reading the TUTOR wrote FOR the learner, not one the learner typed:
  - **Interview-prep reading** (cards 01 · 02 · 03 · 04): a short first-person interview answer, 2–3 short
    paragraphs. Suggested title "Interview: why I want this role" (the title shows on the Scripts row and on
    the result page). The prompter body should read like a prepared answer, not an essay.
  - **News-article reading** (card 05): a short news passage, title reads like a headline. Suggested
    "Today's news: cities are planting more trees". Keep it visibly DIFFERENT from the interview script so
    card 05 reads as a second source, not a repeat.
- **The kit cannot show a "tutor wrote this" scene or badge, and a custom script renders as the kit's
  "내 원고 / My script" genre (pencil.line) — NOT as Explainer/News (brief risk 5).** So the "튜터가 써
  줬다" meaning is carried ENTIRELY by the slide text and the script titles, never by the kit row's genre
  tag. Do not point a sticker or caption at that tag.
- Cover (01) and Outro (06) are PNG stills; cards 02–05 are 8–12 s MP4 loops (`carousel.html?solo=N` →
  `record.mjs`).
- **01 (cover, still):** set `speech.script = {interview-prep}`, then `open()` → the prompter, mic WAITING
  (not recording, camera off). Big prompter body + the mic button hold as a grid still. The "내 원고" list
  row is not on screen here (it's the prompter), so the kit's genre tag never shows — safe.
- **02:** `nw-speech` default Scripts list WITH `speech.script = {interview-prep}` set, so the custom row
  sits at the top of a genre-mixed list (Explainer / Person samples below it). Use `nochallenges` so no
  Challenges section appears (this piece has no board). The list reading as "a shelf of readings" is the
  point; the slide text says they're the tutor's.
- **03:** `open()` → `record()` on the interview-prep script: the prompter scrolls a line at a time and the
  red record chip + timer appear. Do NOT run into the score here.
- **04 (payoff):** on the SAME interview-prep script, `open()` → `record()` → `result(81)`. Because it's an
  own script, the result has NO challenge entry and NO rank sheet (`rankUp` is a no-op) — that absence is
  itself honest: this is private practice. The gauge counts 0→81 (ORANGE, under 85 — honest feedback, never
  a brag), the coach line and the 5-row "측정 결과" (94% · 148 words/min …). The gauge/5 rows may be lifted
  as a sticker. NEVER present 81 / 94% / 148 wpm as a real user's result (brief fact 4).
- **05:** set `speech.script = {news-article}`, then `open()` → the prompter scrolling a line or two. Keep
  it on the prompter (not a second score) so 05 reinforces "news too" without a second payoff brag.
- Outro (06): the fixed series outro — Futureself pill speaking (clipped, light), wordmark, one offer line,
  nawana.app. No plan prices.
- Numbers/titles on every screen are kit sample data (brief fact 4). Futureself mosaic clipped inside the
  pill only.

---

## 01 — Cover: the tutor's reading, now out loud (prompter still, interview-prep script)
eyebrow (ko): 소리 내 읽기 · 01 / 06
title (ko): 튜터가 써 준 글,\n소리 내 읽어요
desc (ko):  면접 준비로 읽던 글, 오늘의 뉴스 기사\n이제 **소리 내 읽고 점수를 받아요.**
footer (ko): 옆으로 넘겨보세요 → · nawana.app

eyebrow (en): Read it aloud · 01 / 06
title (en): Read what your\ntutor wrote
desc (en):  The readings your tutor wrote you,\nnow **read them aloud and get a score.**
footer (en): Swipe → · nawana.app

screen: `nw-speech` `script = {interview-prep}` → `open()` (prompter, mic waiting, camera off, pre-record)
material on screen (stays English): the interview-prep reading body + its title
alt (ko): 스피치 탭 프롬프터에 튜터가 써 준 면접 준비 글이 떠 있고, 아래에 녹음 전 마이크 버튼이 보여요.
alt (en): Cover: the Speech tab prompter showing a tutor-written interview-prep reading, with the mic button waiting below before recording.

## 02 — Your readings gather here (Scripts list, custom row on top)
eyebrow (ko): 소리 내 읽기 · 02 / 06
title (ko): 읽을 거리가\n여기 모여요
title (en): Your readings,\nin one place
desc (ko):  튜터가 써 준 준비 글과 뉴스 기사가\n스피치 탭에 **원고로 들어와요.**
desc (en):  The prep readings and news your tutor wrote\narrive in the Speech tab as **scripts.**

eyebrow (en): Read it aloud · 02 / 06

screen: `nw-speech` `nochallenges` + `script = {interview-prep}` → default Scripts list, custom row at top
note (brief risk 5): the custom row shows the kit's "내 원고 / My script" tag — the slide text, not that tag, carries "튜터가 써 줬다". Don't sticker the tag.
alt (ko): 스피치 탭 원고 리스트예요. 튜터가 써 준 준비 글이 맨 위에 있고, 아래로 여러 읽을 거리가 쌓여 있어요.
alt (en): The Speech tab's list of scripts: a tutor-written prep reading at the top, with more readings stacked below.

## 03 — Read it out loud (prompter scrolling, recording)
eyebrow (ko): 소리 내 읽기 · 03 / 06
title (ko): 소리 내\n읽어요
title (en): Read along\nout loud
desc (ko):  튜터의 글이 프롬프터에서 한 줄씩\n올라가면 그대로 **따라 읽어요.**
desc (en):  Your tutor's reading scrolls up the prompter,\na line at a time, and you **read along.**

eyebrow (en): Read it aloud · 03 / 06

screen: `nw-speech` `open()` → `record()` on the interview-prep script (prompter scrolls, red chip + timer)
material on screen (stays English): the interview-prep reading body
alt (ko): 프롬프터에 튜터의 글이 한 줄씩 올라오고, 빨간 녹음 칩과 타이머가 떠서 따라 읽는 중이에요.
alt (en): The tutor's reading scrolls up the prompter a line at a time while a red record chip and timer show you reading along.

## 04 — Scored the moment you finish
eyebrow (ko): 소리 내 읽기 · 04 / 06
title (ko): 읽자마자\n점수가 나와요
title (en): Finish, and\nyou're scored
desc (ko):  정확도·속도·쉼·군말·목소리 안정감을\n**앱이 바로** 재 줘요.
desc (en):  Accuracy, pace, pauses, fillers, steadiness.\n**The app measures** all five, right away.

eyebrow (en): Read it aloud · 04 / 06

screen: `nw-speech` own-script `result(81)` (gauge 0→81 orange · coach line · 측정 결과 5행, no challenge entry, no sheet)
material on screen (stays English): coach line "Steady and clear…" · 94% · 148 words/min
sticker (optional): the score gauge (81) may be lifted out
note (brief facts 2 · 3): the APP computes the score (not an AI judging you); 81 is orange (under 85) and stays honest; the best take is kept and it can be read again and again.
alt (ko): 읽자마자 점수 게이지가 81점(주황)까지 차오르고, 정확도 94%·148 words/min 같은 다섯 항목이 나와요. 숫자는 샘플이에요.
alt (en): The moment you finish, the gauge fills to 81 (orange) and five rows appear — 94%, 148 words/min and more. The numbers are kit samples.

## 05 — Today's news reads the same way
eyebrow (ko): 소리 내 읽기 · 05 / 06
title (ko): 오늘의 뉴스\n기사도요
title (en): Today's news,\ntoo
desc (ko):  오늘의 뉴스 기사도 같은 식으로\n읽고 **점수를 받아요.**
desc (en):  Today's news article works the same way.\nRead it aloud and **see your score.**

eyebrow (en): Read it aloud · 05 / 06

screen: `nw-speech` `script = {news-article}` → `open()` (prompter scrolling a line or two)
material on screen (stays English): the news-article reading body + its headline-style title
note (brief): a DIFFERENT title/body from 02·04 so the second source reads on screen, not just in words; keep it on the prompter, not a second score.
alt (ko): 프롬프터에 오늘의 뉴스 기사가 한 줄씩 올라와요. 준비 글과 똑같이 소리 내 읽고 점수를 받아요.
alt (en): A today's-news article scrolls up the prompter a line at a time, read aloud and scored just like the prep reading.

## 06 — Outro
eyebrow: none (06 / 06 if the layout shows one)
wordmark: nawana
tagline (ko): 유창한 나에게\n언어를 배우세요.
free (ko): 첫 20분은 무료예요
url: nawana.app

tagline (en): Learn a language\nfrom your fluent self.
free (en): Your first 20 minutes are free
url: nawana.app

screen: `nw-futureself` (speaking), no phone
alt (ko): nawana 워드마크 아래 "유창한 나에게 언어를 배우세요.", "첫 20분은 무료예요", nawana.app이 적힌 마지막 장이에요.
alt (en): Closing card: the nawana wordmark, "Learn a language from your fluent self.", "Your first 20 minutes are free" and nawana.app.

---

## Instagram caption (ko)

준비하려고 읽어 둔 글, 소리 내 읽어 봤어요?

면접 준비로 읽던 글, 오늘의 뉴스 기사.
튜터가 나를 위해 써 준 글이 스피치 탭에 원고로 들어와요.

프롬프터에 한 줄씩 올라오면 그대로 따라 읽어요.
다 읽으면 정확도·속도·쉼·군말·목소리 안정감을 앱이 바로 재 줘요.
AI가 심사하는 게 아니라 앱이 점수를 계산해 줘요.

읽고 점수 받는 데 플랜은 필요 없어요.
가장 잘한 기록이 남고, 몇 번이고 다시 읽어도 돼요.

눈으로 읽던 글이 입으로 말하는 연습이 돼요.

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #영어면접 #nawana

(≈ 300 chars)

## Instagram caption (en)

Got a reading you prepped but never said out loud?

The reading you had for your interview. Today's news article.
Your tutor writes them for you, and they land in the Speech tab as scripts.

They scroll up the prompter a line at a time, and you read along.
When you finish, the app measures five things right away: accuracy, pace, pauses, fillers, steadiness.
It's the app computing a score, not an AI judging you.

No plan needed to read and get scored.
Your best take is kept, and you can read it again as many times as you like.

Reading you only skimmed becomes speaking you practised.

Your first 20 minutes are free · link in bio

#learnenglish #speakingpractice #languagelearning #jobinterview #nawana

(≈ 560 chars)

## Threads (ko)

면접 전에 뭐 읽고 있어요? 그 글, 소리 내서 읽어 본 적은 있어요?

튜터가 써 준 준비 글이랑 오늘의 뉴스 기사를 스피치 탭에서 프롬프터로 읽으면, 정확도·속도·쉼·군말·목소리 안정감을 앱이 바로 재 줘요. AI가 심사하는 게 아니라 점수를 계산해 주는 거예요.

눈으로만 훑던 글이 말하기 연습이 돼요.

첫 20분은 무료예요. nawana.app

(≈ 165 chars)

## Threads (en)

What are you reading before your interview? Have you ever actually said it out loud?

Your tutor writes you a prep reading, and there's today's news article too. Read them on the prompter in the Speech tab and the app measures accuracy, pace, pauses, fillers and steadiness right away. It computes a score, it doesn't judge you.

Reading you only skimmed turns into speaking practice.

Your first 20 minutes are free. nawana.app

(≈ 400 chars)

## Community series entry

cat: practice. New episode, the solo tutor-reading piece (distinct from the Speech CHALLENGE episode, which
is a separate carousel and board). Next unused id after e19 is **e20** — but the `2026-10-12-speech-challenges`
copy.md also wrote itself as e20, so the lead assigns one of them e20 and this one e21 (see open questions).

ko: { title: "소리 내 읽기", tagline: "튜터가 써 준 글을 읽고 점수를 받아요" }
en: { title: "Read it aloud", tagline: "Read what your tutor wrote you, and get a score" }

---

## Open questions (for the lead)

1. **Series id collision.** This entry and the `2026-10-12-speech-challenges` entry both want e20
   (series.json ends at e19; neither is live yet). Assign ids and board order between the two; adding
   either to `series.json` changes the live site → founder approval.
2. **Two custom scripts (brief).** The designer writes an interview-prep reading and a news-article reading
   (both English). Confirm the final titles/bodies read as TUTOR-written (a prepared answer; a headline),
   not as learner-typed notes — the whole "튜터가 써 줬다" meaning rides on them plus the slide text, because
   the kit renders a custom script with the "내 원고 / My script" tag (brief risk 5), which must not be used
   as evidence.
3. **No board, anywhere (brief risk 6).** Confirm every loop uses an OWN script so no challenge entry / rank
   sheet appears (card 04 `result` on an own script; `rankUp` left a no-op). Keep the `2026-10-12` challenge
   piece's board language out of this one.
4. **Numbers stay samples (brief fact 4).** 81 / 94% / 148 wpm are illustrative; captions and alt text say
   so, and 81 is shown orange (honest), never as a perfect-score brag.
5. **"읽고 점수 받는 건 무료" vs "첫 20분은 무료예요" (brief facts 1 · 10).** The piece states reading +
   scoring needs no plan (true — code-computed + free audio read), and the outro keeps the standard
   "첫 20분은 무료예요" (the talk-minutes offer). Confirm the two don't read as one gate, and re-confirm
   `freeGrantSeconds` = 1200 on the post date. No "무료 체험 / free trial" anywhere (there is no trial).
6. **Captions + Threads need approval** before posting (nawana never posts without the founder's OK). All
   well under limits (IG en ≈ 560, Threads en ≈ 400).
