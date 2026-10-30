# Brief — people intro (1.2.3)

> Feature carousel in the "나와나로 할 수 있는 것" series. Carousel shape, BRAND.md, CHANNELS.md
> and the template stay as they are. Copy below is INTENT only — the copywriter writes ko + en
> natively, never translated.

## One message

You can read who a person is — in their own words, in the language you're learning — before you
ever start the call.

(ko intent: 통화를 걸기 전에, 상대가 누구인지 본인이 직접 쓴 소개로, 그것도 내가 배우는 언어로 먼저 읽어봐요.)

If it can't be said in one line, it's two pieces. This is one: the pool stopped being a list of
names and became people with their own stories, and you meet them knowing who they are.

## Who it's for

A learner who's already made a few calls with their fluent self and has noticed the **People**
in the pool — but hesitates to tap Talk on a stranger because a name and a preset voice tell you
nothing, and "무슨 얘길 하지" freezes them. Concrete: 영어 공부 중, 미래의 나와 몇 번 통화해본
사람이 Find people 목록을 열었는데 낯선 이름만 늘어서 있어 선뜻 못 누르던 순간. Honest floor holds —
this reader can already build a sentence and stumble; reading a short first-person intro is within
reach (and is the point).

## Why now

1.2.3 (119) shipped today (fix `cc938a0`): **Find people, a person's page, and the Watch map card
now show the intro that person published** — their first-person self-introduction, written in the
target language. Before this, a stranger in the pool was a name + a preset voice with nothing
saying who they were. Now you see the person before you call. Two things land at once: less friction
("I know who this is, I know what we'd talk about") and free reading practice (the intro is MATERIAL,
so it's in the language being learned).

## Proof in the app

Real behaviour only. From CLAUDE.md "Find people (shared persona pool)" and "A person is a RELATIONSHIP":

- The pool = **strangers + curated characters + other real users**, read per target language.
- An intro is a **PORTRAIT the person published about themselves** — first-person, target language,
  written by `PublicIntroComposer`. It is MATERIAL, so it's in the language being learned.
- **Nothing private leaves the phone.** Only what a person chose to publish is shown — never the
  notebook, never private notes. A published profile can also carry a **face** (a ~96px photo).
- You practice by **TALKING** to them. A stranger's voice is a **preset, never a clone** — the person
  on the other end is a stranger, not your fluent self.

Screens / kit:
- `FindPeopleSheet` — the "People" page (opened from the header `person.2`): your people on top,
  **Strangers** (everyone unmet) below, each row carrying the intro + face. Capture on file:
  `marketing/captures/intake-people.png`.
- A person's **page** — the full published portrait, first-person, in the target language.
- The **Watch map** person card — the intro now rides on the card before you tap Talk.
- Kit today: `web/kit/screens/people.js` renders the Watch tab (people row, two doors, Your
  scenarios, and a person's own card via `CounterpartDetailView`). **It does not yet render the
  published intro portrait** — see Risks.

## Outline (cover → 4 → outro, 6 cards)

Standard carousel: fixed text block on top (series eyebrow 나와나로 할 수 있는 것 · n/6 · pixel
title · 2-line description), live screen below.

1. **Cover** — the message: you can see who you're talking to, before the call.
   *Screen:* Find people list (`FindPeopleSheet`), strangers with faces + intro lines. Must read as a
   still in the grid.
2. **Real people, their own stories** — the pool is strangers, characters and other learners, per
   your target language, each with a published intro.
   *Screen:* Find people list, a slow scroll down the Strangers section. *Sticker:* a single person
   row (face + one intro line) pulled out beside the phone.
3. **Read who they are — in their own words** — the full first-person portrait they published.
   *Screen:* a person's page opening, the intro paragraph settling in.
4. **And it's in the language you're learning** — the intro is MATERIAL, so reading it is practice
   too. *Mark here:* a quiet line that only what they chose to publish is shown — nothing private.
   *Screen:* the person's page, the target-language intro text held for a beat.
5. **So you start the call knowing who you're talking to** — tap Talk, meet them.
   *Screen:* the Watch map person card (intro on the card) → tap → the call opening.
   *Mark here:* a stranger's voice is a preset, never a clone (small footnote-level, not a headline).
6. **Outro CTA** — the standard end card: wordmark · 유창한 나에게 언어를 배우세요. · 첫 20분은
   무료예요 · nawana.app.

## Channels

- **Instagram carousel** (default) — 6 items, 1080×1350. Cover + outro as PNG; cards 2–5 as 8–12 s
  loops where the scroll/open motion helps (cards 2, 3, 5 have motion; card 4 can be a still).
- **Threads** — repost cards 1–5 with a shorter, conversational text (not the IG caption pasted).
- **Community series** (nawana.app/community) — mirror as the next feature-series entry, `cat: "watch"`.
  Next id per `web/community/series.json` (publisher confirms). Founder approval before the entry
  goes live.

## Risks

- **Fidelity gap (blocking for design).** The published intro is a NEW app state the kit doesn't
  render: `people.js` shows the Watch tab + a person's OWN card, not a Find-people row/page with the
  published portrait. Cards 1–4 need a capture + fidelity pass (`marketing/FIDELITY.md`) of the real
  app in 1.2.3 — Find people list, a person's page, and the Watch map card with the intro — before the
  designer can render them. `intake-people.png` may already show the intros; the web agent should check
  and re-capture if not. Flag to the lead; this likely needs mkt-web before mkt-designer.
- **Privacy claim must be exact.** Say "what they chose to publish"; never imply you see anyone's
  private notes or notebook. "Nothing private leaves the phone" is the true line.
- **Don't imply a clone.** A stranger's voice is a preset. Never suggest you'd hear them in your own
  voice — that's the fluent self only.
- **No real user data.** Every face, name and intro on a slide is kit/sample data — never a real
  person's published profile. Don't present sample intros as real users.
- **Honest floor.** Reading an intro in the target language is within reach for the floor reader; keep
  the framing "short, their own words", not "read a paragraph of a language you don't know yet".

## Success signal

- **Marketing surfaces:** saves and shares on the carousel (a "who's in here" piece is shareable),
  profile visits to nawana, link taps, community views.
- **In-app proof (if the founder wants to look):** Find-people **Talk starts** — calls launched against
  a pool persona (`counterpartId` / `remoteId` set) — in the week after. The piece works if more
  learners tap Talk on someone in the pool, which is exactly the friction the intro removes.
