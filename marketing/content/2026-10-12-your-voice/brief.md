# Brief — 내 목소리로 말하는 나와 통화해요 (voice carousel)

> Autopilot run for the 1.1.8 (88) release. The message and screen constraints in `status.md`
> are FIXED; this brief keeps them and fills the gaps (audience, card-by-card outline,
> channels, caption direction, risks, success). Nothing here redesigns the fixed parts.

## One message

**유창한 나는 내 목소리로 말해요 — 이제 더 자연스럽게, 대답도 더 빨리.**
(Evergreen product promise, strengthened. Prompted by 1.1.8's new voice engine; the engine
is the REASON to tell this now, never the subject. Audience doesn't know the old voice, so
no "바뀌었어요 / 업그레이드 / 엔진" framing anywhere — just the promise.)

## Who it's for

The person scrolling Instagram on the way home who studies English on and off — can build a
sentence, stumbles saying it out loud, has tried a phone-English service or a chat app and
felt like they were performing for a stranger. They have never seen nawana. The line that
stops them is "내 목소리로?" — a few years-on version of themselves, already fluent, on the
phone, sounding exactly like them. They leave the carousel wanting to hear their own voice
say the thing they can't yet say.

Honest floor (BRAND): NOT absolute beginners. The call card shows someone forming whole
sentences and getting one small fix — keep it that way; never promise zero-to-fluent.

## Why now

1.1.8 ships a new voice engine for the fluent self's cloned voice: more natural, more like
the learner, faster to answer (`fastlane/metadata/ko/release_notes.txt`). That makes the
core promise — "you learn by talking with your fluent self, in your own voice" — land harder
than it ever has, so it's worth saying to new people now. The piece never mentions the
change; it just shows the promise at its new best.

## Proof in the app (only real behaviour)

- **It's a phone call with your fluent self, in your cloned voice.** Talk = `ConversationView`
  phone-call mode: live STT → Gemini `{reply, suggestion}` → the learner's CLONED voice speaks
  every fluent-self line, auto turn-taking (CLAUDE.md "What this app is", "Talk"). Kit: `nw-call`.
- **The voice is the product.** The user clones their own voice once; "speaker similarity is
  the product — the user must believe the voice is theirs" (CLAUDE.md "Model defaults", TTS).
  The fluent self speaks informally/warmly, never longs or misses (BRAND voice).
- **Why your voice, not a native's** (BRAND "Native-speaker comparison"): imitating a native
  feels like acting; your own voice says "나도 이렇게 말할 수 있구나." Don't belittle natives.
- **It answers fast.** The reply is the only thing the learner waits to hear and the whole
  call path is tuned for it — tap→first word ~2.8 s, reply text landing right after the learner
  stops (CLAUDE.md "A call does not die quietly" / "Nothing in front of the first word may be
  serial", "The reply call may start BEFORE the VAD confirms"). Show it as a natural turn
  cadence, never a number or a loading UI.
- **Awkward bits get fixed mid-call** — a supporting beat only (`suggestion` / fix card). NOT
  the headline of this piece; this one is about the voice.
- **First 20 minutes free, no trial** (`AccountStatus.freeGrantSeconds = 1200`; CLAUDE.md
  billing). Outro only.

## Outline (6 cards: cover → promise → call moment → feels like you → fast → CTA)

Series layout per BRAND (4:5, 1080×1350): fixed text block on top (pixel title + 2-line
description), live kit screen below. Copy intent only — the copywriter writes the Korean
natively (해요체 / noun phrases); the fluent self's on-screen lines stay English as the kit
draws them. Every beat named is one the kit renders.

| # | Card | The one point | Kit screen · beat | Facts to keep true |
|---|---|---|---|---|
| 01 | **Cover** | 내 목소리로 말하는 나와 통화해요 — the hook that makes them stop | `nw-home` beat 1: the call launcher / ring, one tap to call. Still-safe (works as a grid thumbnail). | `ConversationHome`. No price/number on the cover. |
| 02 | **누가 받는가** (the promise) | 몇 년 뒤의 나, 이미 유창한 내가 — 내 목소리 그대로 전화를 받아요 | `nw-call` beat 1: opener appears ("Hey, it's you, a few years from now…"), Futureself speaking. | The caller IS the learner's future self, in their cloned voice. Casual/warm, never longing (BRAND). |
| 03 | **통화 한 통** (hero · the call moment) | 전화하듯 번갈아 말해요 — 내가 말하면, 유창한 내가 대답해요 | `nw-call` beats 2→3: learner's bubble ("I go to three meetings a day"), fluent self answers in the learner's voice; goal chips may tick. A small fix card may land as the reply starts — keep it a side beat, not the point. | Phone-call mode, auto turn-taking; "a turn is answered twice" (the fix is secondary). Correction card shows WITH the voice, never before it. |
| 04 | **왜 내 목소리일까** (feels like you) | 원어민을 따라 하면 연기 같지만, 내 목소리면 '나도 이렇게 말할 수 있구나' — 더 자연스럽고 더 나 같은 목소리 | `nw-call` with the Futureself pill speaking (clipped, light palette), the fluent self's line audible/visible as its own. Optional small `nw-futureself` pill sticker. | "Speaker similarity is the product"; BRAND native-speaker framing (don't belittle natives). This is where 1.1.8's "more natural, more like you" lands — shown as the FEELING, never as "we improved it". |
| 05 | **대답이 바로 와요** (fast) | 말을 멈추면 유창한 내가 바로 대답해요 — 어색한 기다림 없이, 진짜 통화처럼 | `nw-call`: the reply bubble appears promptly after the learner's bubble — a natural turn cadence. | Latency is real (CLAUDE.md). But NO number on screen, NO "typing…" or loading UI, NO benchmark. Just the turn landing without a drawn-out wait. |
| 06 | **Outro / CTA** | 유창한 나에게 언어를 배우세요. · 첫 20분은 무료예요 · nawana.app | Futureself pill speaking (clipped, light), wordmark. The fixed series outro (BRAND). | `freeGrantSeconds = 1200` = 20 min; NO trial. One offer line only; no plan prices in this piece. |

Stickers/comparison: optional on card 04 only (the Futureself pill as a small sticker). No
comparison sticker needed — the whole piece is the voice, so a native-vs-you compare would
duplicate card 04's point. Don't add a corrections sticker; corrections aren't this story.

## Channels (default: IG carousel + Threads + community series)

- **Instagram carousel** — 6 items, 1080×1350. Cover (01) and outro (06) as PNG stills;
  the `nw-call` cards (02–05) as 8–12 s MP4 loops (`record.mjs`) so the turn-taking and the
  pill's speaking motion read. Cover must hold as a still in the grid. Caption ≤ 2,200 chars.
- **Threads** — repost cards 01–05 with a shorter, conversational text (not the IG caption
  pasted). ≤ 500 chars.
- **Community page** — fits the feature series as a **Talk**-category episode centered on the
  voice. FLAG for the publisher/founder: this overlaps `2026-10-11-what-you-can-do` cards
  02–03 (the call + "왜 내 목소리") — extend/point to those, don't ship a near-duplicate
  entry. If it lands as its own episode, keep it tightly about the voice so it's distinct.

## Caption direction (copywriter writes the words)

- **First line = the hook** (shown before "more"): land on hearing your OWN voice speak
  fluently — "내 목소리인데, 내가 못 하는 말을 유창하게 하고 있어요" energy. Not a feature list.
- **Body:** one tap and you're on a call with your fluent self; you talk, it answers in your
  voice, naturally and right away; stumbles get smoothed as you go. Honest floor (not for
  absolute beginners) implied by tone, never stated as a limit.
- **CTA:** 첫 20분은 무료예요 · nawana.app. No prices, no trial language.
- **Hashtags:** 3–5, ko+en mix (#영어회화 #영어공부 #스피킹 …). Never the vendor/engine.
- Register: 해요체. Never "당신", no emoji decoration, no hype words (혁신/최고/revolutionary).
  Written natively in Korean from intent, not translated from English.

## Risks — check before copy/render

1. **No migration framing, anywhere.** No "바뀌었어요 / 업그레이드 / 새 엔진 / 더 좋아졌어요",
   no vendor name. The audience never knew the old voice; this is the promise, full stop.
2. **No accent / voice-settings card** — there is no such kit screen and no capture. The
   release-notes "악센트 '그대로'" option does NOT get a card (status.md decision).
3. **Corrections are a side beat, not the story.** Card 03's fix card may appear as the kit
   draws it; copy must not make "교정" the headline of any card.
4. **"Fast" is shown, never measured.** No latency number, no loading/typing UI, no "0.1초"
   claim. Just the reply landing on a natural turn.
5. **Numbers on screen** (minutes, any score/chip) are kit sample data — never present as
   user results (BRAND).
6. **Futureself mosaic** only clipped inside the pill/circle, light palette — never a
   background texture (BRAND).
7. **Honest floor** — the call shows whole sentences + one small fix; never promise
   zero-to-fluent or "누구나".
8. **Free 20 min, no trial** is the only offer line; no plan prices.
9. **Fluent self never longs/misses** (no "보고 싶었어" / "I missed your voice"); warmth =
   interest in you (BRAND).
10. **Platform-neutral** — voice clone + call work on iOS and Android; don't name a platform
    or an OS version.

## Success signal

Carousel: **saves** (the "I want to try this" signal for a promise piece), **profile visits**
and **nawana.app link taps** in the week after posting, shares, and reach beyond followers.
On the video cards, 3-second hold / average view time (does the voice promise hold the scroll).
Read in the admin 마케팅 tab.
