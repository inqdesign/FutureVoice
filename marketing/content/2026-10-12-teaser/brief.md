# Brief — 티저 영상 (앱 화면 전부, 세로 한 편)

Fixed by the lead (not re-argued here): one continuous vertical video, 1080×1920, 30–40 s
(target **38 s**), light theme, Korean first (EN later), every `web/kit` screen at least
briefly, the call with the fluent self is the hero (open AND close on it), few-word text
beats, Speech = score only.

## One message

**내 목소리로 유창하게 말하는 나와 통화하면, 그 통화가 전부 내 공부가 돼요.**

The teaser carries only the first half out loud (the voice); the montage is the second half
shown, not said ("everything after the call came out of the call").

## Who it's for

Someone scrolling Reels/Shorts who studies English on and off, can build a sentence and
stumbles saying it, and has never seen nawana. They should stop on "that's my voice?" and
leave wanting to hear their own. Not absolute beginners — the call shows someone making
whole sentences and getting one tense fixed; keep it that way.

## Why now

The kit now has every app screen (16) measured from captures, and the series cover carousel
(`2026-10-11-what-you-can-do`) is done, so its approved card-03 voice audio exists. A Reel is
the one format that reaches people who don't follow the account yet — the carousel can't.

## Timeline (38 s, 30 fps)

Layout for every beat: one text beat on top (pixel display face, ≤ 8 Korean words, often
2–4), the `nw-phone` large below. Text intent is given; the copywriter writes the words
(written in Korean from the intent, 해요체 or noun phrases; the fluent self's lines stay
English as the kit draws them). Cuts are hard and on the beat; motion inside a screen comes
from the kit's own `demo()` beats or poses — never drawn.

| t (s) | Screen · moment (kit) | Text beat intent |
|---|---|---|
| **Act 1 — the voice (hero)** | | |
| 0.0–2.6 | `nw-futureself` pill, `mode="speaking"`, clipped, light palette, lit by `3-clone.mp3`'s envelope; the clone's sentence as a caption under it | Caption = the audio line verbatim ("Now I can say what I mean, the way I mean it."); small tag: this is MY voice |
| 2.6–4.4 | `nw-call` beat 1: opener "Hey, it's you, a few years from now…" appears with Futureself speaking | Who's calling: me, a few years on, already fluent |
| 4.4–6.6 | `nw-call` beat 2: coach "try saying" line, learner says "…I go to three meetings a day." | (no new text, or "I just talk") |
| 6.6–8.6 | `nw-call` beat 3: fix card lands ("I **went**…", 과거형 note) as the reply starts | Awkward bits get fixed mid-call |
| **Act 2 — everything after the call (montage, ~1.5 s each)** | | |
| 8.6–10.4 | `nw-ring` beat 1→2: alarm screen "Future …", 8:00, Answer tapped | Rings at the time I set |
| 10.4–11.8 | `nw-home` beat 1: ring tapped | Any topic |
| 11.8–13.2 | `nw-people` beat 1→2: people row fills, a person tapped, sheet up | Or someone I know |
| 13.2–15.0 | `nw-watch` pose `playing` (interview scene, current line ringed) — "Your own situation" door only | See it before it happens |
| 15.0–16.4 | `nw-review` pose `studying` → tap the talk's book card | The call becomes… |
| 16.4–17.6 | `nw-book` `arrived` | …a book of my own |
| 17.6–19.0 | `nw-bookpage` `open("drill")`: said line struck → fixed line | My mistakes, fixed |
| 19.0–20.4 | `nw-words` beat 1: green checks land on used words | Words I actually used |
| 20.4–22.0 | `nw-shadow` beat 1–2: target karaoke, 3·2·1, take | Say it after myself |
| 22.0–24.2 | `nw-sayagain` pose `reading` → scored 92 | The same call again, the right way |
| 24.2–26.0 | `nw-speech nochallenges`: `prompter` → `result` (81) | Read it, get a score |
| 26.0–27.8 | `nw-routine` beat 2→3: day fills, streak flame lights | A promise to myself |
| 27.8–29.4 | `nw-weekreport` pose `coach` (grammar point over my own lines) | My week, read back |
| 29.4–31.0 | `nw-weeklytest` pose `translate-right` | A test made from my week |
| 31.0–32.4 | `nw-progress` beat 2: level swaps to B2 | See where I am |
| **Act 3 — back to the call** | | |
| 32.4–35.0 | `nw-call` beat 3 end: "Three a day? No wonder you sound tired. Which one went best?" Futureself speaking, goal chips tick | Call back to the hook: talk with the fluent me |
| 35.0–38.0 | End card (below) | — |

Pacing note: Act 2 cuts accelerate slightly (1.8 → 1.4 s) and slow again for Say it again
and the return to the call. If 38 s runs long, drop time from `nw-home`/`nw-people`, never
from the hero beats. Say it again at 2 s can't show its `intro` pose, so its text beat must
say "the same call again" (whole call), never "redo your mistakes".

## End card (3 s)

nawana wordmark · **유창한 나에게 언어를 배우세요.** · **첫 20분은 무료예요** · **nawana.app**
(the carousel outro's words, per BRAND). Futureself pill speaking, clipped. Hold the last
frame still for ≥ 1 s so it works as the loop point / thumbnail fallback.

## Sound

- **Silent-safe by construction:** every spoken line is on screen (the caption in 0–2.6 s,
  the call bubbles); nothing depends on hearing.
- **Recommended:** use `2026-10-11-what-you-can-do/audio/3-clone.mp3` (founder's clone,
  2.2 s, "Now I can say what I mean, the way I mean it.") at **0.4 s**, with the pill lit by
  its envelope — the same treatment card 03 got. Founder already OK'd his voice in public.
  On-screen caption must be that exact sentence (the call's opener on screen is a different
  line, so the audio must NOT sit on the `nw-call` beats).
- Optional variant B: cold-open on `1-my-voice.mp3` (founder's own Korean, 5.8 s, Korean
  subtitle "지금의 나") → `3-clone.mp3` ("유창한 나"). Strongest contrast, but costs ~6 s of a
  38 s teaser and pushes the montage to ~1.2 s a screen. Founder's call.
- No music by default (open question). No synthesized call audio beyond these files — the
  call bubbles play silent.

## Channels

Instagram Reel + Story, YouTube Shorts (same file), Threads (video post, short text). Not the
community series (it's a carousel archive). `CHANNELS.md` says Reel/Story "not set up yet —
ask before making one": the lead fixed the format, but the designer needs a new 1080×1920
page (not `carousel.html`) for `record.mjs`.

## Risks — check before render

1. **Daily call is an ALARM screen** (AlarmKit, iOS 26.1+), opt-in. Text must not say
   "전화가 와요"/incoming call; "the time I set" is the true shape. No missed-call banner.
2. **Speech:** `nochallenges` attribute, poses `prompter`/`result` only — never `challenge`,
   `rank-up` or any board/ranking word (not shipped).
3. **Weekly test** shows no flame and no gauge; the flame appears only on `nw-routine` (and the
   report cover, not used here). Don't place the routine flame next to the test cut.
4. **Watch:** your-own-situation door only; no attachment chips (we don't claim it reads files).
   Scenes are counted per plan — never "무제한".
5. **All numbers** (92, 81, B2, streak, minutes) are kit sample data — no text may present
   them as results ("B2 됐어요" no; "where I am" yes).
6. **Progress** is a measured CEFR estimate; don't promise growth ("늘어요") as a claim.
7. **Say it again** = the whole call, not a corrections list (see pacing note).
8. **Free 20 min, no trial** — the only offer line. No prices in a teaser.
9. Android: daily call/alarm shape not verified for Android — keep any caption iOS-neutral
   or don't mention platform.

## Open questions (for the founder)

- Audio: clone line only (recommended) or variant B with the founder's own Korean first?
- Music bed under it, or voice-only/silent?
- EN version now or after the Korean cut lands?

## Success signal

Reel: 3-second hold rate and average watch time (does the voice open hold people), completion
rate, saves and shares, profile visits and nawana.app taps from the profile link in the week
after posting.
