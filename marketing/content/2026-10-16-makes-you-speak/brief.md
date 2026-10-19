# Brief · series 08 · 말을 무조건 하게 만드는 앱 (makes you speak)

Strategist, 2026-10-16. The message and the five-mode order are the founder's (status.md) and
are not re-argued. Intent only: the copywriter writes ko and en natively. Carry-overs from
01–07: light theme, kit screens only, Pixelify wordmark, eyebrow "nawana · NN / 07", cover =
a problem in the learner's words → the answer, ONE story (the interview), no em dash,
captions + Threads REPLY in the series thread + Desktop export.

## One message

**나와나는 무조건 말하게 만들어요. 수준이 어떻든, 어떤 모드든, 결국 내 입으로 소리 내 말해요.**

(en intent: nawana makes you speak, no matter what. Five ways in, and every one ends with you
saying it out loud.)

## Who it's for

Someone who has studied for years (apps, vocab, grammar, videos) and realises they almost
never SAY anything. Scrolling IG, they stop on "you'll speak, whatever your level". Two
readers in one carousel: the one who can hold a conversation and wants real talk (1-0), and
the one whose sentences still come out slowly (1-1). Honest floor: 1-1 is "beginner" in the
sense of 문장이 아직 더듬더듬 나오는 사람, never absolute zero (BRAND). Say "처음 말 떼는",
"아직 말이 잘 안 나오는", not "왕초보도 OK".

## Why now

The founder asked for it as a bundle after 01–07: those are one-feature zooms, this is the
overview a new reader can take in one swipe, and the one sentence the brand keeps saying
("speak, don't study about speaking") finally gets its own piece. Every screen already exists
in the kit, and 02 (shadowing) and 03 (say it again) have choreography to lift.

## The ladder (the reason for this order)

Each card says, in one line, **what comes out of your mouth** in that mode. Read top to
bottom it is a ladder from "your own words" to "a whole speech":

| # | Mode | What you say (intent) |
|---|---|---|
| 1-0 | 프리토킹 (free talk, advanced) | 내 말을 그대로. 주제도 순서도 없이 유창한 나랑 통화해요. |
| 1-1 | 코치 모드 (coach mode, beginner) | 막히면 위에 "이렇게 말해 보세요"가 떠요. 빈칸만 내 얘기로 채워 말해요. |
| 2 | 쉐도잉 | 내 통화에서 유창한 내가 한 한 문장을, 내 목소리 따라 그대로. |
| 3 | 다시 말하기 | 방금 그 통화 전체를 처음부터, 내 차례는 고친 문장으로. |
| 4 | 스피치 | 내가 쓴 원고 한 편을 프롬프터 보고 처음부터 끝까지. |

## Story (one interview, five modes)

Same interview story as 01–07. 1-0: the call after the interview (piece 01's talk). 1-1: the
same call for a learner who's stuck, the coach line fills in the answer. 2: the shadow line
"You clearly took the initiative and prioritized what mattered." (piece 02). 3: the interview
talk's `sample="interview"` (piece 03). 4: their own script "면접 자기소개" (a My script row,
NOT a challenge; challenges belong to `2026-10-12-speech-challenges`).

## Outline · 7 cards

**01 · Cover (still).** Problem, learner's words: 공부는 몇 년 했는데, 정작 말은 해 본 적이
없어요. Answer, bold: 나와나는 무조건 말하게 만들어요. Visual: `nw-futureself` in a circle + the
five modes as a numbered chip list (1-0 프리토킹 · 1-1 코치 모드 · 2 쉐도잉 · 3 다시 말하기 ·
4 스피치). The chips double as the carousel's table of contents. No phone.

**02 · 1-0 프리토킹 · 잘하는 사람은 그냥 말해요.** Say: no script, no topic, a phone call with
your fluent self, it follows whatever you bring up. Screen: `nw-call`, plain (no coach):
`say()` question → `listen()` → `user()` a long, fluent-ish answer → `say()` follow-up that
picks up what they said. A small "B2" style chip is NOT in the app; mark the level only in the
title/eyebrow, not on the screen.

**03 · 1-1 코치 모드 · 막히면 할 말이 떠요.** Say: when you don't know how to answer, a line to
say sits above the call button, with the part only you know left for you, and a word you
studied to try. Screen: `nw-call` `coach({ line, gloss, word })` (pose `coach` exists): the
fluent self asks → coach line "It went <u>really well</u>. I felt <u>prepared</u>." with the
native gloss + "써 볼 단어 · prepared" → `user()` says it with their own fact → the hint ticks
to "썼어요". Optional sticker: the coach line enlarged with "빈칸은 내 얘기". The Call settings
switch (`CallSettingsSheet`) can show for 1 s at the start if the designer has a screen for
it; otherwise omit (see kit gaps).

**04 · 2 쉐도잉 · 한 문장, 내 목소리 따라.** Say: a line your fluent self said in your call,
in your voice; you say it after it and see what the mic heard. Screen: `nw-shadow` target
plays with karaoke → take → result. Lift piece 02's cards 03–04 choreography, compressed to
one card.

**05 · 3 다시 말하기 · 그 통화를, 이번엔 제대로.** Say: the whole talk again, your part the
corrected way, the answers play exactly as they did. Screen: `nw-sayagain sample="interview"`
pose `reading` (corrected line "went" highlighted) → answer plays → next line. Lift piece 03's
card 04.

**06 · 4 스피치 · 원고 한 편을 끝까지.** Say: write your own script (the interview
self-introduction), read it on a prompter, get a score on five parts. Screen: `nw-speech` list
→ tap the own-script row → prompter scrolls → `result(…)` gauge counts up + five rows. No
leaderboard, no camera note (that's the challenge piece).

**07 · Outro (still, unchanged).** Wordmark · 유창한 나에게 언어를 배우세요. · 첫 20분은
무료예요 · nawana.app. Optional closing line above it (copywriter): the cover's promise
answered, e.g. "어떤 모드든, 결국 말하게 돼요."

## Design notes

- **Titles clearly smaller than 01–02** (founder: header font too big). 01–02 used `.ttl`
  72px/88 and cover 110px/130 (`2026-10-11-what-you-can-do/carousel.html`). Target roughly
  `.ttl` 52–56px, cover 72–80px, desc ~28px, so the phone gets more of the card. Founder to see
  card 02 before all are rendered.
- Mode number goes in front of the title as a small label (1-0, 1-1, 2, 3, 4), same style on
  all five, matching the cover chips. Founder's numbering kept as is.
- Video cards 8–11 s each, silent first pass; audio slots like 02/03 later if the founder
  wants (03 coach, 04 shadow, 05 say it again are the natural ones).

## Kit gaps (mkt-web)

1. `nw-speech`: the prompter text is hard-coded (the "Why practise out loud?" sample) and the
   own-script row titles are kit samples ("My team intro for Monday"). Needed: an own-script
   input (title + text) so card 06 can be the interview self-introduction, and a result path for
   an own script (no challenge entry; `noCh` already hides it).
2. `nw-call`: no Call settings sheet with the coach switch. Not required; if wanted on 03, a
   small sheet pose.
3. `nw-shadow` line input: check piece 02's status for whether the `line` object landed; if not,
   reuse its carousel's workaround.

## Channels

- IG carousel, 7 items (01 PNG, 02–06 MP4, 07 PNG), 1080×1350.
- Threads: reply in the series thread. Opens on the problem (years of study, no speaking),
  then the five modes one line each (the ladder table), then "아무 수준에서나 시작해요"-type
  close. ≤500 chars, no hashtags.
- Community: a new entry (it's an overview, not a replacement of e11/e12). Founder approves.

## Facts that must stay true

- Coach mode: a switch in Call settings, ON by default for A1/A2, off above; the learner's own
  flip wins. The "try saying" line appears for every fluent-self line, above the call button,
  with the native meaning; the word hint ("써 볼 단어") is rationed (never before the learner
  has spoken, max 3 a call). Don't say "every word is suggested" or "it answers for you".
- A line READ from the coach suggestion doesn't count as the learner's own evidence. Don't
  claim reading the coach line raises your level/score. Making your own sentence around the
  word hint does count.
- Tutor mode is a different mode (piece `2026-10-13-tutor-mode`); don't blend it into 1-1.
- Free talk: no level label in the app; "advanced" is the piece's framing, not a setting.
- Shadowing target = the learner's cloned voice, the line is the fluent self's from their call.
- Say it again: EVERY learner turn comes up (corrected or as said), answers are the call's own
  audio, never re-synthesized; it never stops on a weak read.
- Speech: own scripts are private, no board; score is code-computed from five parts; numbers
  on screen are sample data.
- Price line only "첫 20분은 무료예요". No trial. Not for absolute beginners. No em dash.

## Risks

1. "무조건" read as pressure/guilt. Keep it a promise about the app (it always gets you
   talking), never a scold of the reader.
2. "비긴너" vs the honest floor (see Who it's for).
3. Seven cards at five modes is dense: each mode card gets ONE sentence, not a feature tour.
4. Overlap with 02/03 (same screens): fine as an overview, but post it not directly after 03.

## Success signal

Saves and shares (an overview saves well), completion to card 06, profile visits from the
thread, and which mode's card gets comments (tells us which mode to lead with in ads).
