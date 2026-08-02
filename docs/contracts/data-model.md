# Data contract

> Language-neutral shape of everything that crosses the wire or will sync.
> Source of truth for the types: `FutureVoice/Models/Models.swift`.
> Source of truth for scoping: `docs/multi-language-plan.md`.

## The scoping rule (this is the whole spec)

> **Every learning record belongs to `(user, lang)`. Every identity/asset record
> belongs to `user` alone.**

Materializations of the same rule:

| Platform | How |
|---|---|
| iOS | language-scoped stores live under `Documents/lang/<code>/` |
| Supabase | a `lang` column on learning tables |
| **Android** | **Room tables keyed by `lang`, from day one** — Android has no single-language legacy to migrate, so it must never build against the single-language assumption |

| Global (`user`) | Language-scoped (`user, lang`) |
|---|---|
| `voiceCloneId`, avatar, native language | `LearnerProfile` |
| subscription / credits (shared pool across all languages) | `Session`, `Drill`, Vocab, Expressions |
| **Personas & Counterparts** — they describe the user's real life; re-entering your people per language is bad UX | `Scenario`, `WatchDialogue`, `WeeklyReport`, `SavedLine`, `Topic`, `NewsTopic`, `ShadowAttempt` |
| cached audio (keyed by text + voiceId hash, so it's shared naturally) | *language-flavored caches on global records* — counterpart topic suggestions, persona situations: key by lang or invalidate on switch |
| active-language pointer + enrolled list | |

**One cloned voice is reused across every language.** ElevenLabs voices are
language-agnostic and the DB enforces one active clone per user — never
re-clone on "add language".

## Server tables (`supabase/migrations/`)

```sql
profiles(id uuid pk → auth.users, native_language text default 'ko',
         target_language text default 'en', proficiency text default 'b1',
         created_at, updated_at)

voice_clones(id uuid pk, user_id uuid → auth.users, elevenlabs_voice_id text,
             is_active boolean default true, created_at)
-- unique partial index on (user_id) where is_active
--   → "switching to a new clone deactivates the old one"

personas(...)  -- JSONB blob mirroring UserPersona; schema-on-read
```

Everything else (counterparts, scenarios, dialogues, attempts, drill cards) is
**local-only** today. Android must assume the same and keep its Room DB
authoritative for those.

### The magic moment

A user who cloned on iPhone signs in on Android → read the active row from
`voice_clones` → the FIRST thing they hear on the new device is their own voice.
**Never rebuild cloning UX as Android's first step.** Restore is enough for v1.

## Core types

```jsonc
// The unit of a conversation.
Turn {
  id: uuid,
  role: "user" | "fluentSelf",
  audioURL: string?,              // local file ref; not synced
  transcript: string,
  durationMs: int,
  timestamp: datetime,
  suggestion: TurnSuggestion?,    // load-bearing — see behavior.md §4
  fluency: FluencyStats?,         // user turns only, measured
  excludedFromScoring: bool = false
}

TurnSuggestion { alternative: string, reason: string }

FluencyStats {
  speakingSeconds: double,        // voiced time
  totalSeconds: double,           // voiced + mid-speech silence
  pauseCount: int,                // mid-utterance silences ≥ 0.35s
  pauseSeconds: double,
  longestPauseSeconds: double
}

WordTiming { word: string, startMs: int, endMs: int }

Session {                          // language-scoped
  id: uuid, userId: uuid, targetLanguage: string,
  mode: "pronunciation" | "conversation",
  topic: string?,
  startedAt: datetime, endedAt: datetime?,
  turns: Turn[],
  summary: SessionSummary?,
  archivedAt: datetime?,
  origin: "free" | "news" | "scenario" | null,
  originScenarioId: uuid?
}

LearnerProfile {                   // language-scoped (keyed by language in-file)
  id: uuid, userId: uuid, targetLanguage: string,
  proficiencyLevel: "a1"|"a2"|"b1"|"b2"|"c1"|"c2",
  recurringMistakes: LearnerPattern[],
  weakVocabAreas: string[],
  strongPatterns: string[],
  totalSessions: int,
  totalSpeakingSeconds: int,
  lastSessionAt: datetime?,
  summaryEmbedding: float[]?
}

LearnerPattern { id: uuid, mistake, correction, context: string,
                 frequency: int, lastSeenAt: datetime }

SessionSummary {
  phrasesUsed: PhraseFeedback[],
  newPatternsDetected: LearnerPattern[],
  suggestedDrills: string[],
  overallNote: string,
  scorecard: SessionScorecard?,
  newWordsUsed: string[], expressionsUsed: string[], weakVocabAreas: string[],
  grammarIssues: GrammarIssue[], carryovers: Carryover[]
}

SessionScorecard {
  vocabulary|grammar|expressiveness|fluency: AxisScore,
  pronunciation: AxisScore?,       // null until shadow drills exist
  topLine: string,
  cefrLevel: string?               // holistic read, a1…c2
}
AxisScore { score: 0..100, note: string }

GrammarIssue { quote, correction, note }   // correction fixes grammar only,
                                           // nothing restyled
```

## The conversation turn payload (wire shape, order fixed)

```jsonc
{ "reply": "...",
  "suggestion": { "alternative": "...", "reason": "..." } | null,
  "transcript": "..." | null }
```

`transcript` is the verbatim utterance **as heard from the attached audio**, and
is `null` when the turn carried no audio (which is the Android v1 case — see
`README.md` §Known parity gaps).

## The learning loop — every client must close it

```
conversation → summary (+ deterministic scorecard metrics) → DrillStore.ingest (SRS cards)
            ↘ LearnerProfile.absorb → next conversation's system prompt
            ↘ WeeklyReportEngine (unlocks on accumulated speaking time)
```

Any feature that doesn't feed this loop doesn't belong in either client.
