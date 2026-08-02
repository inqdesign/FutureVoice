# Behavior contract

> Deterministic rules that must produce the **same result on every platform**.
> These are not tuning knobs a port gets to re-pick. A client with different
> numbers here is a different product.
>
> Hard rule this whole doc serves: **deterministic scores stay deterministic**.
> Shadow match scores and scorecard metrics are computed in code; the LLM only
> writes qualitative notes anchored to those numbers. Never let an LLM invent a
> number the code can compute.

## 1. Audio format

| Purpose | Format |
|---|---|
| Speech capture for STT / cloning input | **16 kHz mono 16-bit PCM WAV** |
| Voice-clone high-quality sample | 44.1 kHz mono 24-bit PCM WAV |
| TTS streaming playback | 16-bit **LE** mono PCM @ **22050 Hz** (`X-Audio-Format: pcm_22050`) |
| TTS buffered playback | MP3 |

16 kHz mono PCM WAV is accepted by both Whisper and ElevenLabs. **Don't change
it without checking both providers' docs.**

## 2. Turn-taking / endpointing (the Talk loop)

Hybrid endpointing, the same shape modern realtime voice stacks use:
**acoustic VAD picks the endpoint, text completeness modulates how long to wait.**

### Energy → "voiced"

Level curve: `rms` of the mic buffer converted to dBFS and mapped to 0…1
(`0.35` on the curve ≈ **−32.5 dBFS**).

| Constant | Value | Meaning |
|---|---|---|
| `baseVoicedThreshold` | `0.35` | Absolute "this is speech" floor. |
| `noiseMargin` | `0.12` (≈ 6 dB) | How far above the measured noise floor a frame must sit to count as speech. |
| `noiseRisePerSecond` | `0.03` (≈ 1.5 dB/s) | Decaying-minimum noise estimate ("minimum statistics") rise rate. |
| effective threshold | `max(baseVoicedThreshold, noiseFloor + noiseMargin)` | |
| `minPause` | `0.35 s` | Silence run that counts as one pause/hesitation. |

The noise floor **snaps down** instantly to a quieter level and **rises slowly**
(`noiseRisePerSecond`), so a burst of the user's own speech can never push the
threshold above their voice. Rationale: outdoors and in cafés ambient runs
−40…−25 dBFS, i.e. at or above the absolute floor — without adaptation the
endpointer reads street noise as speech and the turn never fires.

### Three-tier wait, measured against TRUE AUDIO SILENCE

Silence is measured from **last voiced audio**, never from "last transcript
change" (STT partials stall unpredictably while the user is still talking).

| Tier | Wait | Fires when the trailing transcript… |
|---|---|---|
| long | **5.0 s** | is clearly mid-thought — trailing filler, hanging conjunction, or a stub article/preposition; or ≤ 2 words with no terminal punctuation |
| short | **1.2 s** | ends in terminal punctuation `.` `!` `?` |
| default | **2.2 s** | anything else |

Supporting constants:

| Constant | Value | Meaning |
|---|---|---|
| `sttSettleSeconds` | `0.7 s` | Don't send while the partial is still changing (recognition lag after the last spoken word is typically 0.3–0.5 s). |
| `endpointTickSeconds` | `0.2 s` | Monitor tick — worst-case added latency ≤ one tick. |
| `noisyRoomFallbackSeconds` | `6.0 s` | Steady background noise can keep the meter reading "voiced" forever; fire on transcript-quiet as an upper bound. |
| `preconnectAfterSilenceSeconds` | `0.6 s` | Warm TLS + auth token during the wait, once per listening phase. |
| `quietCommitThreshold` | `1.5 s` | STT segment rotation (commit the live segment, start a new one). |

Send condition:

```
(audioSilence >= tierWait AND sinceTextChange >= 0.7)   // audio path
OR sinceTextChange >= 6.0                                // noisy-room path
```

…and **never with an empty transcript**.

Word lists that pick the long tier (lowercased, punctuation-stripped last word):

- fillers: `uh um er ah hmm mm well 음 어 그 그러니까 에`
- trailing conjunctions: `and but or so because cause if when while that which though although`
- trailing function words: `the a an to in on at of for with by from into about`

Telemetry per turn (keep the key names — dashboards read them):
`vad_wait_ms`, `vad_path` (`audio`|`noisy`), `text_quiet_ms`, `noise`,
`finalize_ms`, `gemini_ms`, `tts`, `tts_first_ms`, `total_ms`.

## 3. Early-field streaming (why the reply is fast)

The turn schema is `{ "reply", "suggestion", "transcript" }` and **field order is
load-bearing**: the client fires TTS the instant `reply`'s **closing quote**
arrives, while the model is still writing the tail. Every character emitted
before `reply` is silence the user sits through.

The scanner must:
- find `"<field>"`, skip whitespace, require `:`, skip whitespace, require `"`;
- decode escapes `\n \t \r \" \\ \/` and `\uXXXX` while scanning;
- return the value **only** at the unescaped closing quote (nil while still
  streaming);
- return nil for a non-string value, so `"suggestion": null` never reads as a
  finished string;
- bail (nil) on a `\uXXXX` surrogate half — it can't be resolved one escape at
  a time; let the fully decoded payload win.

**Do not add a field before `reply` and do not reorder the prompt's schema line.**

## 4. Suggestions are part of the loop — never optional

Per-turn suggestions come back in the SAME Gemini call as the reply. Do not add
a second per-turn LLM call, and do not drop the field: `suggestionRate`, drill
ingestion, and the weekly report's repeated-mistake detection all depend on it.

A suggestion is dropped as junk when `alternative` is empty or looks like a
meta-rule.

## 5. Drill cards (SRS)

Leitner boxes **0–5**. Box 0 stays due immediately.

| Box | Next review |
|---|---|
| 0 | now |
| 1 | +1 day |
| 2 | +3 days |
| 3 | +7 days |
| 4 | +14 days |
| 5 (max) | +30 days |

- Correct → `box = min(box + 1, 5)`.
- Wrong → `box = max(box - 1, 0)`.
- **Used spontaneously in conversation** → jump `min(max(box + 2, 3), 5)` —
  real use is worth more than a drill rep. Never demote on this path.

**Cards must be speakable utterances, never meta-rules** ("use articles
correctly" is a bug). `looksLikeMetaRule` is the safety net; prompts must emit
concrete sentences.

## 6. Shadow match score (deterministic)

```
tokens   = lowercase, split on anything outside [alphanumerics ' -]
           (contractions collapse to one token)
           .syllable style → additionally explode each word into characters
alignment = standard DP edit-distance over token arrays
raw       = matches / max(targetTokens, learnerTokens)
score     = round(sqrt(raw) * 100), clamped 0…100
```

The `sqrt` curve is deliberate: it softens the bottom so a single-word slip
doesn't crater an otherwise good attempt. Reanchored so **90+ excellent,
75 good, <60 noticeable**.

Token style comes from the language, not the caller:

| Style | Languages | Why |
|---|---|---|
| `word` | en, es, de, fr, it, pt | whitespace-delimited |
| `syllable` | ja, ko, zh | spacing is absent (ja/zh) or too unstable in STT output (ko) to compare on |

## 7. Language table

| code | STT locale | token style | graded wordlist |
|---|---|---|---|
| en | en-US | word | `cefr_words` |
| es | es-ES | word | — |
| de | de-DE | word | — |
| fr | fr-FR | word | — |
| it | it-IT | word | — |
| pt | pt-BR | word | — |
| ja | ja-JP | syllable | — (ship gate: JLPT-graded list) |
| ko | ko-KR | syllable | `cefr_words_ko` (국립국어원, 2003) |
| zh | zh-CN | syllable | — |

Nothing outside this table may hardcode a language. Adding one = one entry
(+ optional bundled resources).
