# Review — 2026-10-13-tutor-mode — 2026-10-13 (round 2)
Verdict: PASS

Round-1 FIX items all resolved:

1. [truth] Toggle name — the KO side now names the switch **튜터 모드** everywhere the reader
   turns it on (card 01 desc "통화에서 **튜터 모드**를 켜면"; card 05 footer "튜터 모드는 꺼져
   있어요 · 통화 설정에서 켜세요"; IG caption line 1; Threads line 1; community-entry ko title
   "튜터 모드"). "수업" survives only as the common noun for what it does ("수업이 돼요",
   "수업을 이끌어요", "수업을 해줘요") — never as the switch. CTA is 켜면 / 켜세요. EN says
   "tutor mode." Matches the ship build: `CallSettingsSheet` draws `Label("Tutor mode",
   systemImage: "graduationcap")`, ko catalog value "튜터 모드". RESOLVED.

2. [truth] Off-by-default framing — the "starts on / it starts on" claim is gone. Card 05
   footer states "튜터 모드는 꺼져 있어요 · 통화 설정에서 켜세요" / "Tutor mode is off · turn it
   on in call settings"; IG/Threads say "켜기 전엔 꺼져 있으니 … 켜보세요" / "off until you turn
   it on." No "on by default" and no "for beginners." Matches `TutorMode.isOn =
   UserDefaults.bool(forKey:)` (plain bool, no level resolve; `CallSettingsSheet` default
   false). RESOLVED.

3. [fidelity] No Coach-mode surfaces anywhere — across all six stills and the mid-animation
   frames of 03/04, teaching appears ONLY as the fluent self's spoken `say()` bubble
   ("We'd say: I went to three meetings.", "Good. With friends, just: I'm Mina."), with the
   kit's karaoke highlight lighting the words as the pill speaks. No `fix` correction card
   (✕ was / ✓ now), no "이렇게 말해 보세요 / Try saying", no "써 볼 단어 / Try using", no
   "썼어요 ✓ / Used it", no `coach` pose. The only per-line affordance is the standard "뜻"
   meaning toggle (real `DialogueLine` call chrome, present in any call). RESOLVED.

Full pass — all clean:
- Truth: lesson every turn, taught aloud in the own cloned voice, feedback = right-way /
  more-natural / "Good."+step-up then a practice question — all verified against
  `tutorBlock` (ConversationEngine.swift) and `TutorMode`/`CoachMode.swift`. "Practice call,
  not graded" is accurate (`Session.coached`) and never overclaims "nothing counts"; the
  copy keeps 점수 없는 연습 통화 while minutes/streak/corrections→cards still stand.
- Price/limit: "첫 20분은 무료예요" / "first 20 minutes are free" matches `freeGrantSeconds`
  1200; no trial copy; no plan prices on any slide. Correct.
- Voice: KO reads as native 해요체 product copy (돼요 / 없어요 / 들려줘요 / 얹어줘요 / 편해요 /
  켜세요); fluent-self lines are English material so no register conflict; no "당신"; EN native.
- Visual: light theme, blue #0A5CF5 accent, green/red within palette; Futureself mosaic
  clipped inside the pill (01/03/04/05 + outro 06); real `nw-call` chrome; titles 2 lines;
  01/06…06/06 consistent; text legible, no overflow/clipping; key moment in frame on every card.
- em dashes: none in any posted or alt string (card descs/titles, IG caption ko+en, Threads
  ko+en, alt text ko+en). The "—" that remain are only in internal JS/CSS comments and
  markdown headers/designer-notes — not shipped.
- Channel: 6 × 1080×1350; durations 01 8s / 02 10s / 03 10s / 04 7s / 05 10s / 06 4s (all
  ≤60s; hero 03/04 within the 8–12s guide — round-1's 13s 03.mp4 is now 10s); IG caption
  ko ≈300 / en ≈650, Threads ko ≈190 / en ≈400 (≤500); 4 ko + 4 en hashtags (3–5 range).
- Safety: sample name "Mina" (not the founder's name); "three meetings today" is kit sample
  data, not presented as a stat; no real user data or testimonials.

## Suggestions (non-blocking)
- Card 04 uses "My name is Mina." → "Good. With friends, just: I'm Mina." The step-up here is
  a register move (shorter/casual) rather than a "more useful" word; it's a faithful instance
  of tutorBlock part 1c, just the lightest of the three example types. Fine to ship; a slightly
  richer step-up would sell the "한 걸음 더" title harder.
- Community e06 id, captions and Threads still need founder OK before posting (noted in copy's
  open questions) — process, not a content defect.

Checked frames: renders/01–06.png (final stills) + 03.mp4 @5s @8s (karaoke teaching beat) +
04.mp4 @5s (step-up beat). Durations: 01 8s · 02 10s · 03 10s · 04 7s · 05 10s · 06 4s.

PASS — 0 FIX
