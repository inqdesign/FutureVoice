# Edge Function API contract

> Base URL: `<SUPABASE_URL>/functions/v1`
> Every client (iOS, Android) talks to providers ONLY through these. No client
> ever holds a Google or ElevenLabs key.

## Common to every function

| Header | Required | Notes |
|---|---|---|
| `Authorization: Bearer <supabase access token>` | yes | `requireUser()` verifies it; 401 otherwise. |
| `X-Idempotency-Key` | yes | Missing → `400 missing X-Idempotency-Key header`. The usage ledger dedupes **charges** on this key, so a retry of the SAME logical request is free. |
| `Content-Type: application/json` | yes (except voice-clone upload) | |

### Status codes the client MUST special-case

| Status | Meaning | Client behavior |
|---|---|---|
| `402` | Out of credits (`insufficientCreditsResponse`) | Surface the paywall/credit copy — never a raw error. iOS: `GeminiError.insufficientCredits` / `ElevenLabsError.insufficientCredits`. |
| `4xx/5xx` | Upstream or auth failure | Body's first 512 bytes are the only diagnostic a beta tester can screenshot — keep them in the error. |

### Idempotency key shapes used by iOS (mirror them)

- Conversation turn: caller-supplied, stable across the turn's retry ladder
  (streamed attempt → buffered retry share ONE key → ONE charge).
- TTS without a caller key: `tts:<installSalt>:<sha256(voiceId|withTimestamps|text)[0..12] hex>`.
  Salted per install so keys can't collide across users on shared preset voices.
  Plain and `with_timestamps` syntheses are separate billable actions and must
  NOT dedupe against each other — that's why the flag is inside the hash.
- Everything else: a fresh UUID.

---

## `POST /gemini`

Proxy for `generateContent` / `streamGenerateContent`, with a credit gate.

### Request

```jsonc
{
  "model": "gemini-3.6-flash",          // see Model defaults below
  "system_instruction": { "parts": [ { "text": "<system prompt>" } ] },
  "contents": [
    { "role": "user",  "parts": [ { "inlineData": { "mimeType": "audio/wav", "data": "<base64>" } },
                                  { "text": "<asr text>" } ] },
    { "role": "model", "parts": [ { "text": "<prior model turn, re-wrapped as the turn JSON>" } ] }
  ],
  "generationConfig": {
    "temperature": null,                 // gen-3: OMIT. 2.5 only: caller's value
    "maxOutputTokens": 1024,
    "thinkingConfig": { "thinkingLevel": "low" },   // gen-3
    // "thinkingConfig": { "thinkingBudget": 0 },   // 2.5 family
    "responseMimeType": "application/json"          // only when JSON is wanted AND no search grounding
  },
  "tools": [ { "google_search": {} } ],  // omit unless grounding
  "purpose": "summary",                  // optional billing tag, stripped before upstream
  "stream": true                         // optional; true → SSE passthrough
}
```

`model`, `purpose` and `stream` are consumed by the Edge Function and stripped;
everything else is forwarded to Google verbatim.

**Rules that are not negotiable**

- An **audio part is sent FIRST**, the text rides along as the ASR hint.
- Only the FINAL user turn carries audio; earlier turns stay text-only to keep
  the request small.
- History is capped at the last **12 turns** (~6 exchanges).
- Model turns in the history are re-wrapped in the SAME JSON envelope the turn
  call must produce (`{"reply": ..., "suggestion": null, "transcript": null}`),
  because with plain-text model turns the model imitates its own past
  formatting and drifts out of JSON mode a few exchanges in.

### `purpose` → billed action

| `purpose` | action | 
|---|---|
| `"summary"` | `gemini_summary` |
| `"weekly"` | `gemini_weekly` |
| `"enrichment"` | `gemini_enrichment` |
| absent / anything else | `gemini` |

### Response — buffered (`stream` absent/false)

Google's `generateContent` body, passed through:

```jsonc
{ "candidates": [ { "content": { "parts": [ { "text": "..." } ] }, "finishReason": "STOP" } ] }
```

Client extracts `candidates[0].content.parts[*].text` joined, then — for JSON
calls — takes the substring from the FIRST `{` to the LAST `}` before decoding.
`finishReason == "MAX_TOKENS"` reclassifies a decode failure as *truncated*
(raise `maxOutputTokens`), and must only be consulted AFTER parsing has
actually failed.

### Response — streaming (`stream: true`)

- Handshake header: **`X-Gemini-Stream: sse`**. Its absence means this deploy
  ignored `stream` and sent one plain JSON body → buffer and decode normally,
  no early fire. (Degradation path, must stay supported.)
- Body: `text/event-stream`. Lines prefixed `data:`; each event is one
  `generateContent` candidate carrying that step's **text delta**. `[DONE]` and
  empty events are skipped.
- The client accumulates the deltas into one raw string and watches for a
  named field's CLOSING quote to fire early (see `behavior.md` §Early-field
  streaming).

Degradation ladder for a broken stream:
1. Dies **after** the early field → rebuild the payload from what arrived; the
   user still hears the turn.
2. Dies **before** it → throw; the caller retries non-streaming on the SAME
   idempotency key (no second charge).

---

## `POST /elevenlabs-tts`

### Request

```jsonc
{
  "voice_id": "<elevenlabs voice id>",
  "text": "<already in the target language>",
  "model_id": "eleven_turbo_v2_5",
  "with_timestamps": false,
  "stream": false,
  "purpose": "turn"        // "turn"|"scene"|"shadow"|"drill"|"library"|"greeting"
}
```

Voice settings are fixed **server-side** (`stability 0.55`, `similarity_boost 0.90`,
`style 0`, `use_speaker_boost true`) so they can be tuned without a client
release. **`style` MUST stay 0** — any exaggeration pulls output away from the
reference speaker, which is the one thing this product sells.

`purpose: "greeting"` with `text.length <= 120` is **free** (the clone's first
words are part of onboarding, not usage). Length-capped so the tag can't smuggle
real synthesis.

### Model choice (this is a product decision, not a perf knob)

| Path | model_id | Why |
|---|---|---|
| Live Talk turns | `eleven_turbo_v2_5` | Flash was tried and reverted: same price, lower speaker similarity, on the app's highest-exposure surface. |
| Watch scenes (user's own voice), onboarding greeting | `eleven_multilingual_v2` | Fidelity tier; markedly better cross-lingual transfer. |
| Shadow, drills, library, preset counterpart voices | `eleven_turbo_v2_5` | |

`eleven_multilingual_v2` bills ~2x per character upstream while pricing here is
character-based and **model-blind** — that 2x is margin absorbed. Only put a path
on it when the result is **cached** (one-time per unique line) or it fires once
per user, ever. **Never** for live turns.

### Responses

| Mode | Accept | Response |
|---|---|---|
| Buffered | `audio/mpeg` | MP3 bytes |
| Streaming (`stream: true`) | — | Raw **16-bit LE mono PCM @ 22050 Hz**, with header **`X-Audio-Format: pcm_22050`**. Absence of that header means an older deploy returned a whole MP3 — buffer it and take the classic path. |
| `with_timestamps: true` | `application/json` | `{ "audio_base64": "...", "alignment": {...}, "normalized_alignment": {...} }` where an alignment is `{ characters: string[], character_start_times_seconds: number[], character_end_times_seconds: number[] }`. Prefer `normalized_alignment`. |

`stream` and `with_timestamps` are mutually exclusive (server ignores `stream`
when timestamps are asked for).

`X-Credits-Balance` is set on every success.

Client chunking rule for the PCM stream: flush to the player every **~8 KB**
(~0.18 s at 22.05 kHz s16 mono), and **never split an Int16 across flushes**
(always flush an even byte count).

Timestamp → word timing conversion (must match across platforms): group
consecutive non-whitespace characters into a word; the word's window is
`[first char start, last char end]`, rounded to **milliseconds**. Mismatched
array lengths → return no timings (never guess).

---

## `POST /elevenlabs-voice-clone`

`multipart/form-data`:

| Field | Value |
|---|---|
| `name` | display name, e.g. `"Eunggyu — Future Self"` |
| `description` | optional |
| `remove_background_noise` | `"true"` / `"false"` — decided from the MEASURED SNR of the take, never hardcoded. Denoising a *clean* take shaves breath/sibilance/high-end, i.e. exactly the cues that make a clone recognizable. |
| `files` | one or more WAV/MP3 parts. Total 30–60 s recommended. |

Response: `{ "voice_id": "..." }`.

Failure to know about: upstream `400` whose body contains `voice_limit_reached`
is OUR capacity problem — show a human message, not the upstream JSON.

## `POST /elevenlabs-voice-delete` — `{ "voice_id": "..." }`
## `POST /elevenlabs-voice-rename` — `{ "voice_id": "...", "name": "..." }` (free, no credits)

---

## Auth

- **iOS**: Sign in with Apple → `signInWithIdToken` (native token, no browser
  round-trip), nonce = `sha256(rawNonce)` in the Apple request, raw nonce handed
  to Supabase.
- **Android**: the SAME Supabase user must be reached or the voice clone can't
  be restored. Apple has no native Android SDK, so Android uses Supabase's
  **web OAuth** flow for the `apple` provider (Custom Tab → `futurevoice://`
  callback). Adding Google later means deciding identity linking first — two
  providers with one email are two Supabase users unless linked, and a split
  identity silently costs the user their clone.

## Model defaults

| Use | Model |
|---|---|
| Conversation turns, learner-facing coaching text, analysis | `gemini-3.6-flash`, `thinkingLevel: "low"`, DEFAULT sampling |
| Utility (pure translation, counterpart parsing, canned openers) | `gemini-3.1-flash-lite` |
| Rollback hatch only (retires 2026-10-16) | `gemini-2.5-flash` — takes `thinkingBudget: 0` + explicit temperature |

Gen-3 models: Google recommends against sub-1.0 temperature; the client DROPS
the caller's temperature for them. Only the 2.5 family honors it.
