# Future Voice — MVP Spec

> Learn a language by speaking with a fluent version of yourself.
> 자신의 유창한 미래 버전과 대화하며 언어를 배우는 앱.

**Owner:** Eunggyu / RoRo Company
**Status:** Concept → Prototype
**Platform:** iOS-first (SwiftUI)
**Date:** 2026-05

---

## 1. Core Concept / 핵심 컨셉

The user clones their own voice once. The app uses that clone to synthesize a *fluent* version of their voice in the target language. The user then practices speaking and listening against this "future self" — and over time, the AI learns their specific speech patterns and surfaces more natural alternatives.

사용자가 자신의 목소리를 한 번 클로닝한다. 앱은 그 클론을 사용해 타겟 언어로 *유창하게 말하는* 버전의 목소리를 합성한다. 사용자는 이 "미래의 자신"과 말하기·듣기 연습을 하고, 시간이 지남에 따라 AI가 사용자의 말 습관을 학습해 더 자연스러운 표현을 제안한다.

---

## 2. Three Modes

### 2.1 Pronunciation Practice / 발음 연습
- User picks a phrase or word.
- Hears their *fluent self* say it.
- Records their attempt.
- Sees waveform comparison + AI feedback on specific sounds.

### 2.2 Conversation Practice / 대화 연습
- User picks a topic or scenario (e.g. "ordering coffee", "job interview", "small talk").
- Voice-driven open conversation with the fluent self.
- Real-time turn-taking. No scripts.

### 2.3 Refinement Summary / 정제 요약
After each conversation, the user sees:
- Phrases they used → more natural alternatives the "fluent self" would have used.
- Recurring patterns or mistakes.
- 2–3 suggested phrases to drill next.

---

## 3. The Loop / 학습 루프

```
record  ─►  detect       ─►  surface         ─►  learner
              conversation     natural             profile
              patterns         alternatives        grows
```

Each session feeds the next.

---

## 4. Tech Stack / 기술 스택

| Layer | Tool | Notes |
|---|---|---|
| UI | SwiftUI | iOS-first |
| Audio | AVAudioEngine / AVAudioPlayer | record, play, waveform |
| STT (on-device) | **SpeechAnalyzer** (iOS 26) | Real-time transcription |
| STT (fallback) | **Whisper API** | Higher accuracy when needed |
| Voice cloning | **ElevenLabs API** | Voice clone + fluent TTS |
| LLM | **Anthropic Claude API** | Conversation, pattern detection, rephrasing |
| Backend | **Supabase** | Auth, learner profile, session summaries, audio storage |
| Local persistence | **SwiftData** | Offline-first session cache |
| Subscriptions | **RevenueCat** | Paywall, sub management |

---

## 5. Data Model — see `FutureVoice/Models/Models.swift`

Domain types are defined in code as the source of truth. The spec types
listed below map 1:1 to the Swift structs:

- `User`
- `LearnerProfile` (per target language) — long-term memory
- `LearnerPattern` — mistake/correction with frequency
- `Session`, `Turn`, `SessionSummary`, `PhraseFeedback`

---

## 6. Key Flows

### 6.1 Onboarding (one-time)
1. Sign up → pick native + target language(s).
2. **Voice cloning step**: user reads a 30–60s ElevenLabs prompt out loud.
3. Upload audio → ElevenLabs `/v1/voices/add` → get `voice_id`.
4. Save `voice_id` to user profile.
5. First fluent-self preview: app says a welcome line in target language. **Magic moment.**

### 6.2 Pronunciation Session
1. User picks phrase from a curated list (or types one).
2. Tap play → fluent self speaks it (ElevenLabs TTS w/ user's voice_id, target lang).
3. Tap record → user repeats.
4. On-device STT transcribes user's attempt.
5. Claude compares transcript + waveform timing → returns per-sound feedback.
6. Show waveform overlay + colored feedback markers.

### 6.3 Conversation Session
1. User picks a topic.
2. Fluent self opens with a prompt (Claude generates → ElevenLabs synthesizes → play).
3. User taps and holds to speak (or auto-VAD).
4. STT transcribes locally → send to Claude with learner profile context.
5. Claude responds → ElevenLabs synthesizes → play.
6. Repeat for ~5–10 turns or until user ends.
7. **Post-session**: Claude generates `SessionSummary` from transcript + profile.
8. Update `LearnerProfile.recurringMistakes` and embeddings.

---

## 7. Prompts — see `FutureVoice/Services/ConversationEngine.swift`

Prompt templates live in code so they can be iterated without doc edits.

### 7.3 Context compression
- Keep the last 3 sessions' raw summaries.
- Compress older history into `LearnerProfile.recurringMistakes` (top 10 by frequency).
- Use embeddings on session summaries for semantic recall when topics repeat.

---

## 8. Audio Handling

- **Recording format**: 16kHz mono PCM WAV (matches Whisper + ElevenLabs).
- **VAD**: SFSpeechRecognizer built-in, or roll a simple amplitude+silence detector.
- **Playback**: AVAudioPlayer for synthesized fluent-self audio. Pre-fetch when possible.
- **Latency target**: < 1.5s from user end-of-speech to response start.
  - On-device STT: ~200–500ms
  - Claude turn: ~800ms
  - ElevenLabs TTS: ~400–700ms (streaming endpoint)
- **Storage**: last 30 days of session audio in Supabase Storage. Delete older unless user pins it.

---

## 9. Pricing Hypothesis

| Tier | Price | Includes |
|---|---|---|
| Free | $0 | 1 voice clone, 5 conversations/month, basic summary |
| Pro | $14.99/mo or $89/yr | Unlimited conversations, full pattern memory, side-by-side voice comparison |
| Lifetime | $299 | Everything, forever (early-adopter promo) |

Voice cloning is the moat → free up front to maximize activation.

---

## 10. Build Phases

### Phase 1 — Voice + Conversation Spike (1–2 weeks)  ← **WE ARE HERE**
- SwiftUI shell, single screen.
- Clone one voice end-to-end (ElevenLabs).
- One hardcoded conversation: record → STT → Claude → TTS → play.
- **Goal**: hear yourself fluent for the first time.

### Phase 2 — Learner Profile (2–3 weeks)
- Supabase schema + auth.
- Session save/load.
- Post-session summary generation.
- LearnerProfile updates.
- Test: does the AI feel like it "remembers" you after 5 sessions?

### Phase 3 — Closed Beta (4–6 weeks)
- Onboarding flow.
- Pronunciation mode (in addition to conversation).
- Topic picker.
- TestFlight to ~10 friends across KR / DE / EN.
- Watch for: does the loop actually feel rewarding? Where do they drop off?

---

## 11. Open Questions

- [ ] How do we handle the user's accent in the *clone*? Refine over time, or accept as part of voice identity?
- [ ] Should the fluent self ever speak the native language (e.g. for translation), or always stay in target language?
- [ ] Pronunciation feedback: text-based explanation, visual waveform overlay, or both?
- [ ] How to avoid losing teachable moments because corrections come post-session?

---

## 12. References

- ElevenLabs Voice Cloning API: https://elevenlabs.io/docs/api-reference/voices/add
- Anthropic Claude API: https://docs.claude.com
- Apple SpeechAnalyzer (iOS 26): WWDC 2025 session
- AVAudioEngine: Apple developer docs

---

*Built on the same philosophy as Dear RoRo — person before product.*
