# brief — accent-words (1.2.1)

- **stage:** brief → copy
- **channels:** IG carousel (6 cards) + Threads (first 5) + community series entry (new `e20`, cat `talk`)
- **series:** "나와나로 할 수 있는 것" — this is a Talk-category feature piece; extends the Talk run (e02–e05), doesn't repeat it. No existing episode touches accent.

## The one message

악센트를 영국식으로 고르면, 유창한 나는 그 소리만 내는 게 아니라 그 동네 말을 써요 — flat, lift, queue. 그리고 내가 쓴 apartment, elevator는 절대 틀린 게 아니에요. 내 목소리로, 내가 고른 악센트로, 거기 사람들이 실제로 쓰는 말.

(EN, for the en column: Pick a British accent and your fluent self doesn't just *sound* British — it *talks* British (flat, lift, queue), every turn of the call. And your own "apartment" or "elevator" is never marked wrong. Your voice, your accent, the way people actually speak there.)

If the piece can only land one thing: **the accent changes the WORDS, not just the sound — and your side of the conversation is never corrected for it.**

## Who it's for

A learner who cares *which* English (or Spanish) they're learning, and was quietly let down that the app always leaned American. Concrete person/moment: 영국으로 교환학생·취업·워홀을 앞두고 영국 영어로 말버릇을 맞춰두고 싶은 사람; 또는 그냥 영국식(또는 호주식) 영어가 좋은데 지금껏 앱·튜터는 늘 미국식이라 아쉬웠던 사람. Castilian Spanish를 쓰는 스페인행 학습자도 같은 자리.

Honest floor respected: this is someone already building sentences and choosing a variety — not an absolute beginner. The piece never promises fluency; it shows one setting doing exactly what it says.

## Why now

1.2.1 (build 112) ships it — commit `3709fd0e`, CLAUDE.md "The accent also picks the WORDS (2026-10-20)" (`ConversationEngine.varietyGuard`, `VoiceAccentCatalog.writingVariety`). Accent-picking existed before as sound only; from this release the chosen variety also steers the words across the whole call (and corrections, scenes, voicemail, coach — we show the call).

## Proof in the app

- **Screen:** `web/kit/screens/call.js` (`nw-call`) only. The accent *picker* screen is NOT in the kit, so do not show a picker UI — tell the whole story through the live call's transcript.
- **Behaviour shown is real:** the fluent self's lines come out in British-variety vocabulary (`writingVariety` adds a LANGUAGE VARIETY line to the reply prompt); the learner's own cross-variety words are never swapped or flagged (`varietyGuard` — "the learner's words from another variety are never a mistake and never swapped"). So in card 3 there is **no correction card** — the absence is the proof.
- **The app does not paint variety words in a special colour.** The transcript just contains them. Any emphasis (circling flat/lift/queue) is a **sticker outside the phone frame** or lives in the card's top text block — never drawn onto the app screen (BRAND: show the app as it is).
- `call.other` stays unset → the other side is the fluent self ("미래의 나" / "Future self"). That is the point: it's YOUR voice in the accent you picked, not a British stranger.

## Outline (6 cards)

**Card 1 — Cover** (still PNG; must read in the grid)
- Says: 악센트가 소리만 바꾸는 게 아니에요 — 단어까지 바꿔요. / The accent picks the words, too.
- Screen: none (cover layout). Series eyebrow + pixel title. Optionally one small sticker: a line bubble reading "…take the **lift** down…" peeking from the bottom.

**Card 2 — Your fluent self talks British** (`nw-call`, motion: `say`)
- Says: 영국식을 고르면 통화 내내 영국 말이 나와요. / Pick British, and the whole call goes British.
- Screen script: `other` unset; chips/goals e.g. `["brilliant", "round the corner", "lift"]`. Fluent-self line via `call.say(...)`:
  "Brilliant to hear from you! Fancy a quick coffee? There's a lovely spot just round the corner — take the lift down to the ground floor."
- Sticker (optional, outside frame): underline/circle **fancy · round the corner · lift**.

**Card 3 — Your own words are never wrong** (`nw-call`, motion: `user` then `say`, NO `fix`)
- Says: 내가 쓴 apartment, elevator는 틀린 게 아니에요. 그냥 flat, lift로 답해줄 뿐. / Your "apartment" and "elevator" stay yours — it just answers in "flat" and "lift".
- Screen script: learner turn `call.user("I can't, I'm stuck in my apartment waiting for the elevator guy.")` → **no correction card appears** → fluent-self reply `call.say("No worries — sounds like your lift's playing up. I'll pop round to your flat instead.")`
- The blank space where a correction card would sit is the whole point. Copy may say "교정 카드 없음" is intentional; designer must not add a `fix(...)`.

**Card 4 — Every turn, and not only English** (`nw-call`, frozen two-turn British exchange, or reuse card 2's pose)
- Says: 한 줄이 아니라 통화 전체예요. 영국식 · 호주식 영어, 스페인은 카스티야식. / Not one line — the whole call. British & Australian English; Castilian for Spanish.
- Screen: a settled British exchange (one fluent-self line + one learner line). Keep text block carrying the "which accents" fact.
- Copy must say the default accent (American English / Mexican Spanish) and "no accent" change nothing — the word-swap is only for a non-default variety. (Keep this light; it's a precision note, not a disclaimer.)

**Card 5 — Your voice, your accent** (text-forward; stickers)
- Says: 내 목소리로, 내가 고른 악센트로, 거기 사람들이 실제로 쓰는 말. / Your voice, your accent, the way people really speak there.
- This is the differentiator card (BRAND: AI tutor speaks in someone else's voice; the fluent self speaks in mine — so "flat" sounds like *I* could say it). Screen: the Futureself pill, or the call frame dimmed, with 2–3 word stickers (flat / lift / queue) from the transcript rising around it. No new UI invented.

**Card 6 — Outro** (standard outro)
- Wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" · nawana.app. No price claims beyond the free-minutes line.

## Risks / things to check before ship

- **Which accents actually swap words:** only non-default varieties — **British English, Australian English, Castilian Spanish** (`writingVariety`). Do NOT claim American English or Mexican Spanish "change the words" — they're the defaults and add nothing. "No accent" also adds nothing.
- **No internal numbers on any card.** The measured before/after (reply British-vs-American word counts) is internal only — it may give the copywriter confidence but must not appear as a stat.
- **No invented screen highlight.** The app doesn't colour variety words; emphasis is sticker/top-text only.
- **No correction card on card 3.** If a `fix(...)` sneaks in, the piece says the opposite of the truth.
- **Demo vocabulary:** British words used (flat, lift, queue, brilliant, fancy, round the corner, pop round, playing up, ground floor, no worries) are genuine BrE variety — fine. Keep the full demo in English (target default); mention Australian/Castilian in words only, don't fake a Spanish transcript.
- **Threads text** is written fresh (conversational), not the IG caption pasted. Hook line about picking British and hearing "flat/lift/queue" back in your own voice.

## Success signal

Afterwards look at: saves + shares on the carousel (a "I didn't know it did this" setting reveal tends to save well); comments/DMs asking "does it do Australian / British?" (demand signal → worth a follow-up); community `e20` views. Secondary: any uptick in accent-sheet use post-release (PostHog, if an event exists) — not a launch-day metric, a 2-week read.

## Community series entry (for publisher, draft only)

- `id: e20`, `cat: "talk"`, `slides: 6`
- ko: title ≈ "악센트가 단어까지", tagline ≈ "영국식을 고르면 통화 내내 영국 말이 나와요"
- en: title ≈ "The accent picks the words", tagline ≈ "Pick British and the whole call goes British"
- (Copywriter finalizes titles/taglines in copy.md; these are placeholders.)
