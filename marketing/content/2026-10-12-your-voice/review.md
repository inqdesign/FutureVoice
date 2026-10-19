# Review — 2026-10-12-your-voice (voice carousel) — 2026-10-12
Verdict: PASS

No FIX items. Every gate checked and held:

- **Truth.** "첫 20분은 무료예요 / Your first 20 minutes are free" matches `freeGrantSeconds = 1200`
  (BRAND "First 20 minutes free, no trial"). No plan prices, no trial language anywhere. No
  invented feature or screen state — cover ring, `Future self` label, 뜻 button, fix card, goal
  chips and the speaking pill are all real `nw-home`/`nw-call`/`nw-futureself` kit pieces. On-screen
  sample numbers ("오늘 목표 10분") read as kit data, never presented as user results.
- **No migration/engine/vendor framing.** Grepped copy.md: 업그레이드/엔진/바뀌 appear only in the
  internal "don't use these" instruction (line 4). Nothing on any card, caption or Threads body names
  the 1.1.8 change, a vendor, or "faster than before".
- **App fidelity.** Card 03 flow (opener → learner bubble → fix card landing WITH the reply → fluent
  self answers) matches ConversationView; the fix card appears after the reply begins, never before
  (script: `reply = s.say(...)` then `s.fix(...)`), consistent with "correction shows with the voice".
- **Voice.** Fluent-self lines are casual native English ("Hey, it's you, a few years from now…",
  "Three a day? No wonder you sound tired. Which one went best?", "Want to run the opening line by
  me?") — warm, interested, never longing/missing. App voice (titles, desc, fix note "지난 일이라
  과거형이에요") is 해요체; positive-first; no "당신". Korean and English each read as natively written.
- **Honest floor.** Card 03 shows the learner forming whole sentences and getting one small tense fix
  (go → went), not zero-to-fluent / 누구나.
- **Visual.** All frames 1080×1350; title (2 lines) + desc (2 lines) sit in the fixed block; key
  moment inside the card; iOS-native; legible contrast; palette held (ink, blue #0A5CF5, light-blue
  me-bubble). Futureself mosaic is clipped inside the pill (cards/outro) and the ring circle (cover)
  only — never a background. Card numbers consistent 01/06…06/06. No blank/half-faded start (card
  text present from t=0; opener text visible by ~1 s).
- **Fast (card 05).** Natural turn cadence only — no latency number, no "typing…"/loading UI, no
  benchmark. Bottom status lines are authentic app chrome.
- **Channel fit.** 6 items; cards 02–05 are 8.5–11.6 s loops (≤60 s), cover/outro PNG stills. IG
  caption ko ≈230 / en ≈490 chars (≤2,200), hook on first line, 4–5 ko+en hashtags (never the vendor).
  Threads ko ≈190 chars (≤500). Posted caption + Threads bodies carry no "—" em dash.
- **Safety.** No real user/founder data or name, no invented testimonials, no impersonation, native
  comparison is fair ("copying a native feels like acting") and does not belittle.

## Suggestions (non-blocking)
- Cards 02 and 04 leave a large white upper area in the phone (empty call transcript at call start).
  It reads as an authentic just-opened call, but a slightly higher pan or an earlier bubble would make
  the speaking pill feel less isolated at feed-scroll speed. Taste only.
- The en alt-text on card 04 (copy.md line 95) uses an em dash. Alt text is accessibility metadata,
  not a posted caption, so it does not block; swap it for a comma if the publisher surfaces alt text.

Checked frames: renders/01.png · 02.mp4 @1s 4s 7s · 03.mp4 @2s 5s 7s 9s 11s · 04.mp4 @1s 3s 5s 7s ·
05.mp4 @2s 4s 6s 8s · 03.png · 05.png · 06.png
