# futurevoice-gateway

Realtime Talk relay on Cloudflare Workers + Durable Objects — Phase 1 of the
industry-standard voice pipeline (see CLAUDE.md's latency notes for why the
per-turn HTTP pipeline can't get there).

```
iPhone ──(1 WebSocket per call)── CallSession DO
                                    ├── gemini-3.5-transcribe-live (streaming ASR +
                                    │     server-side utterance endpointing, barge-in witness)
                                    ├── gemini-3.6-flash streamGenerateContent (reply text,
                                    │     thinkingLevel "minimal", speculative fire on
                                    │     settled interim — adopted only on word match)
                                    ├── ElevenLabs multi-context WS (cloned voice, turbo,
                                    │     pre-warmed at session start)
                                    └── Supabase (auth + voice ownership, ONCE per call)
```

Why not a Gemini Live half-cascade session: as of 2026-08-31 every
conversational Live model on the Gemini API is audio-output only (probed —
`test/probe-live-setup.mjs`), and this product's voice must be the learner's
ElevenLabs clone. So the gateway runs its own cascade; the transcribe-live
model still gives us server-side semantic-ish endpointing.

**Measured (local `wrangler dev`, 2026-08-31): speech-end → cloned voice
2.5–2.9 s** (old per-turn HTTP pipeline: ~6.5 s p50). Breakdown: utterance
finalization ~1.4 s (Gemini's clock, the floor for now) + adopted speculative
reply + EL first audio ~1.1 s. Expect somewhat better on the real edge.

## What's in / not in Phase 1

- ✅ Auth (Supabase JWT) and voice ownership (same deepfake rule as
  `elevenlabs-tts`) enforced at session start.
- ✅ Turn-taking, barge-in, input transcription, reply streaming, TTS context
  rotation, Gemini session rotation (~15 min cap → resumption handle).
- ⏳ Metering: speech seconds counted and reported (`stats` events), **not
  billed yet** — Phase 3 wires `charge_talk_seconds`/talk-tick.
- ⏳ Per-turn `{reply, suggestion}` correction: the suggestion moves to an
  async flash call client-side (it's already display-deferred); not here.

## Setup

```bash
cd gateway
npm install
npx wrangler secret put SUPABASE_URL
npx wrangler secret put SUPABASE_ANON_KEY
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npm run deploy
```

Local dev: put the same keys in `.dev.vars` (gitignored), plus
`DEV_ALLOW_ANON=1` to skip auth, then `npm run dev`.

### Config knobs (vars, not secrets)

- `GEMINI_LIVE_MODEL` — defaults to `models/gemini-3.1-flash-live-preview`
  (verified available on the production key 2026-08-31 via
  `test/check-live-models.py`; re-run it when Live model names churn). We
  need the half-cascade (TEXT response modality), never native-audio,
  because the voice must be the learner's ElevenLabs clone.
- `ELEVEN_OUTPUT_FORMAT` — `pcm_22050` default; `pcm_44100` needs the Pro
  plan (the edge function's format ladder learned this per-instance; here
  it's explicit config).

## Smoke test (no app build)

```bash
npm run dev            # with .dev.vars incl. DEV_ALLOW_ANON=1
node test/talk.mjs --url ws://localhost:8787/call --wav hello16k.wav \
  --voice <a real clone or preset voice id>
```

Prints every event with ms timestamps and writes reply audio to `out.wav`.
The headline number is `first reply audio — N ms after last mic frame`.

Make a test wav: `say -o /tmp/h.aiff "I went to a cafe yesterday and it was
really nice" && afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/h.aiff hello16k.wav`

## Design decisions worth keeping

- **One DO per call, `newUniqueId()`, nothing persisted.** The object IS the
  call; the transcript's system of record stays the iOS `SessionStore`.
- **The client does no turn-taking.** Mic PCM streams continuously; Gemini
  Live's server VAD decides turns and interruptions. The whole client-side
  VAD/spec/chunk machine in ConversationView is unnecessary on this path.
- **Barge-in audio hygiene**: a closed context's in-flight chunks are dropped
  in the DO (`activeContext` gate) AND the client must flush its local buffer
  on `interrupted` — both halves are needed or the voice talks over the
  learner who just interrupted it.
- **EL socket reconnects lazily** (`ensureConnected` at reply start): the
  multi-context socket idles out at ≤180 s server-side, and a long learner
  monologue would kill a keep-alive design; worst case a turn pays one
  reconnect on a warm TLS session, never a failure.
- **`limits.cpu_ms` is raised** in wrangler.jsonc — messages on OUTBOUND
  sockets bill the open invocation context, and a 30-min call of PCM frames
  would eventually trip the 30 s default.

## Phase 2/3 (not started)

iOS client (`RealtimeTalkClient`) behind a debug flag; barge-in playback
flush; billing (server-side speech-seconds → existing RPCs); telemetry
parity (`talk_turn_timing` from gateway timestamps); Android reuses this
gateway as-is.
