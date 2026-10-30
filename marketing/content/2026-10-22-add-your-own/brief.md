# Brief · 직접 추가 (Add your own) — library series

Strategist, 2026-10-22. Autopilot upload, build 1.2.2 (118). Intent only; copywriter writes ko
and en natively from the intent, never translating one into the other. Source commits:
`a3a9ff86` (직접 입력해 목록에 추가), `ac47da0b` (입력하는 대로 이미 있는 항목 찾아 주기),
`70175c26` (레벨 달린 하나의 공유 라이브러리). Extends the library series (e13 단어장, e14 표현,
e15 문장 카드): those showed the lists filling THEMSELVES from talks. This one answers the next
question — "내가 밖에서 주운 단어도 넣을 수 있어요?" — yes, and it studies itself the same way.

## One message

**밖에서 주운 단어·표현·문장도 목록에 직접 넣으면, 통화에서 나온 것과 똑같이 공부가 돼요 —
타이핑하는 대로 이미 있는 건 떠서 두 번 안 만들고, 새 건 레벨을 달고 내 목소리로 읽어 주고
덱·복습·위젯이 알아서 가르쳐요.**

(en intent: a word you met anywhere — an article, a meeting, a coworker's phrase — drops straight
onto your list and then rides the exact same loop as a word your fluent self used: it gets a CEFR
level, your own voice reads it, and the deck, review and widget take over. As you type, anything
already there surfaces, so you never make a duplicate.)

## Who it's for

The learner who collects words in the wild and has nowhere good to put them: reads "leverage" in a
work email, hears a phrase a coworker keeps using, wants it IN their study — but opening a separate
Anki deck is a chore and the word rots in a Notes app. Already uses nawana's Words/Expressions
pages (or came from a notebook habit). Can build a sentence, stumbling — honest floor, not an
absolute beginner.

## Why now

- Build 118 just shipped it. The library series (e13/e14/e15) taught that your lists fill
  themselves from talks; the obvious follow-up question — "can I add my own?" — had no answer until
  now. This closes the gap for anyone who has opened those pages and looked for a "+".
- It is a Practice/Review piece, so it slots behind e13/e14/e15 in the same series and the same
  category (`practice`). Don't repeat the words/expressions pieces — this is the door INTO those
  lists.

## Proof in the app (HEAD code — every claim)

- **"+" top-right on Words, Expressions and Sentences** (`WordsView` `showingAdd` → `justAdded`
  opens the card after; `ExpressionsView`, `SentencesView`) → one sheet, `AddToListSheet`.
- **Type it in either language.** Target language stays as written; a native-script entry (사과
  while learning English) is turned into the target language and SHOWN for confirmation before it
  is added (`needsConverting` / `converted` / `Translator`). Only script tells the two apart —
  German typed by an English learner reads as English (a real limit, don't claim otherwise).
- **Find-as-you-type ("Already there").** As they type, prefix matches first, up to 6, each with
  its first-sense meaning (free, cached `WordLore`). For words the search includes the graded word
  pool; for expressions the shared-library phrases. Tapping a match OPENS that card — never a copy
  (`open`, `DrillStore.saveIfNew` already collapses duplicate sentences). A pool word nobody has
  kept yet shows its level and a "+"; tapping keeps it and opens it.
- **A new item is checked once, then leveled and shared** (`SharedLibrary.add` → `library-add`,
  3.6-flash). A typo comes back as "Did you mean …" and adds nothing; made-up words, chat slang,
  names of people/places/brands, another language, offensive words, and a phrase typed into the
  word slot are refused with a plain reason. It passes → it is stored as its dictionary form with
  a **CEFR level** and joins `library_terms`, the ONE library everyone learning that language draws
  from. The level is the ITEM's, not the learner's.
- **Then the ordinary loop, for free.** Word → studying + its card opens with meanings; expression
  → bookmarked; sentence → a review card with the native translation under it (`bookmarkSentence`).
  Everything saves through the existing store paths, so sync, the daily deck, review and the
  home-screen widget follow with nothing extra (`VocabStore`, `DrillStore`).
- **The card reads in the learner's own cloned voice** (`WordCard.fullCard` pronounce button,
  `PhraseAudioStore`) — the same card e13/e14 showed. Not a native or tutor voice.
- Kit: `nw-words` — the leveled cloud + the word card (headword · level · meaning · the clone
  pronounces it), grounded in `marketing/captures/vocab.png`. The add-input / "Already there"
  moment has no capture; the designer may add a faithful pose to `nw-words`, else carry the story
  through the cloud and card the additions feed. **Do NOT draw a new screen.**

## Outline · 6 cards (eyebrow "nawana · NN / 06")

**01 · Cover (still).** 밖에서 주운 단어, 목록에 바로. Second line: 넣으면 통화에서 나온 단어처럼
알아서 공부가 돼요. Screen/sticker: `nw-words` cloud with a small "+" sticker and one word landing
on it (a level tag attached). Works as a grid still.

**02 · 직접 넣어요.** Say: tap "+" on your Words list and type what you met — in either language.
Screen: `nw-words` with the add sheet, typing a hero word (suggest **"leverage"**; designer's call
from the kit list). Poster: the add field + the headword. [Kit gap 1 — add-input pose.]

**03 · 입력하는 대로, 이미 있는 건 떠요.** Say: as you type, what's already on your list (and in the
word pool) surfaces with its meaning — tap it instead of making a twin. Screen: the "Already there"
list under a stem (e.g. "pre…" → prepare · perspective · prioritize), one marked Studying, one a
pool word showing its level + "+". Message: no duplicates, ever. [Kit gap 1.]

**04 · 새 단어는 레벨을 달고 모두의 라이브러리로.** Say: a word the library doesn't have yet is
checked once (a typo gets a "혹시 이건가요?", a made-up word is turned away), then stored with a CEFR
level — in the one library everyone learning English shares. Screen: the hero word landing on the
cloud with its level badge (e.g. B2). Keep "그 단어가 다음 학습자에게도 도움이 돼요" warm, never a
privacy claim — nothing personal is shared (who added is server-only, for rate limiting). [Kit gap 2.]

**05 · 그다음은 통화에서 나온 단어와 똑같아요.** The payoff. Say: now it is just like a word your
fluent self handed you — hear it in your own voice, it's in today's deck, on your home-screen
widget, in review. Screen: the word card with the pronounce button pressed (Audio W1), then a beat
on the Vocabulary widget sticker. Poster: the card in your voice. [Kit gap 2 — word card/deck; the
widget is a sticker + caption, no kit screen.]

**06 · Outro (unchanged).** wordmark · 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 ·
nawana.app.

## Audio

- **W1 · founder's Cartesia clone:** the hero word once, relaxed pace, on card 05 only (e.g.
  "leverage."). Optional: its first-sense example line after a ~0.6 s pause, if the kit card carries
  one. No learner take needed.

## Channels

- **IG carousel**, 6 items (01 PNG, 02–05 MP4, 06 PNG). First line of the caption is the hook
  ("밖에 주운 단어, 외우려고 적어만 두죠"). 3–5 hashtags, ko+en mix.
- **Threads**, repost cards 01–05 with a shorter conversational text (not the IG caption): the loop
  in one line (어디서 주운 단어든 넣으면 → 레벨 달고 → 내 목소리로 → 덱·위젯까지), "소리 켜고 5번째
  장". ≤ 500 chars.
- **Community series**: a NEW entry, `cat: practice`, next free id (series jumps e18→e19, so e20 or
  the founder's pick). Mirrors the IG carousel at 720×900. Founder approval before deploy.

## Risks / copy traps

1. **The CEFR level is the WORD's, not the learner's.** Never imply "we read your level from what
   you add." Say "단어마다 레벨이 붙어요", not "네 레벨을 매겨요".
2. **"Shared with everyone" is a feature, not a privacy ask.** Only the term + level + language are
   shared, and only after the check passes. Who added it is service-role only (rate limiting).
   Don't claim a community size, a count, or that your personal study is shared.
3. **Don't over-promise the check.** It turns away typos, made-up words, names, other languages and
   phrases-in-the-word-slot — say that honestly; don't frame it as a flawless dictionary.
4. **Not "memorize a wordlist."** Lead with "밖에서 주운 걸 바로 공부로", the using loop, not rote.
5. **The voice is the learner's clone**, not a native/tutor voice. Keep e13/e14 consistency.
6. Numbers on slides (levels, counts, "To study" figures) are kit sample data — never user stats.
7. Honest floor: not for absolute beginners; never promise zero-to-fluent.

## Open questions

- **Server live?** The feature needs the `library_terms` migration + the `library-add` function
  deployed, or an add of a word not already in the library is blocked ("사전에 연결하지 못했어요").
  Confirm build 118's server is live before the carousel ships, or cards 03–04 can't be captured as
  working. (Product/founder check, not a copy decision.)
- **Kit pose for the add moment?** `nw-words` has no add-input / "Already there" capture. Designer:
  add a faithful pose from the Swift source, or tell cards 02–03 through the cloud + a real add-sheet
  sticker. Flagged as kit gaps 1–2; no invented screen.
- **Hero word.** Suggested "leverage" (plausibly met in the wild, above a casual floor, not reused
  from e13's "compelling"). Designer confirms against the kit cloud sample.
- **Community id.** e06 and the e18→e19 jump leave id choice to the founder; default e20.

## Success signal

- Saves and Threads replies from the "I collect words but never study them" crowd (Anki/Notes
  migrants).
- Product (PostHog, read-only): `own_item_added`, `own_item_matched` (find-as-you-type catching
  duplicates), `own_item_refused` (typo/reject rate — if high, the check reads as a wall, revisit
  card 04's copy). A week after posting, whether added items get said in a call (the library loop
  closing).
