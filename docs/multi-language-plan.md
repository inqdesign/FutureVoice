# Multi-Language Architecture Plan (v2)

> One user, one subscription, many languages — with easy switching.
> Status: PLAN (not yet implemented). v1 2026-07-29; v2 same day after direct code verification, with Android as a standing premise.

## Decisions locked
- **Language switcher**: always visible in the Talk header (Duolingo-style chip). Adding/removing languages + per-language CEFR live in the Me tab.
- **Voice clone**: ONE cloned voice reused across every language. No re-clone on "add language" — ElevenLabs voices are language-agnostic and the DB already enforces one active clone per user.
- **Subscription**: stays global. `user_subscriptions` + `user_credits` are per-user with no language column — "one subscription, many languages" is already satisfied. Credits are a shared pool across all languages.

## The contract (platform-neutral — this is the real spec)

> **Every learning record belongs to `(user, lang)`. Every identity/asset record belongs to `user` alone.**

Materializations of the same contract:
- **iOS today**: language-scoped stores move under `Documents/lang/<code>/`
- **Supabase Phase 2** (already promised in ProfileStore/SessionStore header comments): a `lang` column on learning tables
- **Android**: Room tables keyed by `lang`

Design the iOS work against the contract, not the other way around — then the multi-language work doubles as the Android/server data spec.

### Global (`user`) vs language-scoped (`user, lang`)

| Global | Language-scoped |
|---|---|
| `voiceCloneId`, avatar, native language | LearnerProfile (already keyed by language in-file) |
| subscription / credits | Sessions, Drills, Vocab, Expressions |
| **Personas & Counterparts** (v2 change — they describe the user's real life; re-entering your people per language is bad UX) | Scenarios, WatchDialogues, WeeklyReports, SavedLines, Topics, NewsTopics, ShadowAttempts |
| cached audio (text+voiceId hash — shared naturally) | *language-flavored caches on global records*: counterpart topic suggestions, persona `situations` (disk key `"englishSituations"` is the breadcrumb) — key by lang or invalidate on switch |
| active-language pointer + enrolled list | |

## Switching mechanism (v2 — corrected)

**v1's `.id(activeLanguage)` view trick is NOT sufficient.** Stores are process-lifetime singletons with in-memory caches (`SessionStore.shared` caches the decoded array behind an NSLock and reads the file once per launch — SessionStore.swift:14–45; stores also call each other's singletons directly, e.g. SessionStore → `DrillStore.shared.deleteForTurn`). Re-creating views leaves singleton caches pointing at the old language.

The mechanism is store-level:
1. `LanguageScope.switchTo(code)` → each registered store (a) re-resolves its fileURL under `lang/<code>/`, (b) flushes its in-memory cache.
2. `.id(appState.targetLanguage)` on the root of the language-scoped view tree remains as a *complement* to reset view state.
3. Reload `learnerProfile` via `ProfileStore.shared.load(targetLanguage:proficiency:)` — this pattern already exists in AppState (FutureVoiceApp.swift:539).
4. Re-run `StudyWidgetRefresher`.
5. Block/safe-save switching during an active conversation or recording.

## Phases

### Phase 0 — Scope infrastructure
- New `Services/LanguageScope.swift`: active + enrolled state, `lang/<code>/` URL helper (created on demand), store registration + `switchTo` fan-out (re-resolve URL, flush cache).
- `FutureVoiceApp.swift` (AppState): `enrolledLanguages: [String]` (UserDefaults `futurevoice.enrolledLanguages`, default `["en"]`); `switchLanguage(_:)` / `addLanguage(_:cefr:)` / `removeLanguage(_:)`. Do NOT call `regenerateVoiceClone` on add.

### Phase 1 — Store scoping
Scope under `lang/<code>/` + add cache-flush hook: SessionStore, DrillStore, VocabStore (6 files), ScenarioStore, WatchDialogueStore, ShadowAttemptStore (+ Recordings/), SavedLineStore, TopicStore, NewsTopicStore, WeeklyReportStore.

Keep GLOBAL at root: ProfileStore (already keys by language in-file), **PersonaStore, CounterpartStore** (v2 — global records, language-keyed caches), PhraseAudioStore / TurnAudioStore, AvatarStore, VoiceSampleStore.

**Trap fix — `VocabStore.matchesKorean`** (VocabStore.swift:377–381): process-lifetime `static let` reading UserDefaults once. Must become instance/scope-resolved so a runtime switch re-picks the lemmatizer route. Same check for `CoreVocabulary` launch-scoped reads.

### Phase 2 — Switching wiring
Implement the store-level switch above; wrap language-scoped view tree in `.id(...)`; guard against switching mid-conversation.

### Phase 3 — UI
- **Talk header switcher** (`ConversationHome`): current-language chip → enrolled list + "Add language".
- **Add-language flow** (variant of `SetupFlowView`): remove hardcoded `"en"` (SetupFlowView.swift:32), add target picker (exclude the user's native language); SKIP the voice step; set CEFR; call `addLanguage`. First-run onboarding gains the target choice too.
- **`MeTab`**: language management section; proficiency picker becomes per-language (reads/writes the per-language LearnerProfile — already per-language in ProfileStore).
- **`LanguageCatalog.nativeLanguages`**: add `"en"` (the "intentionally absent — fixed target" comment at LanguageCatalog.swift:55 no longer holds once the target is selectable).

### Phase 4 — Migration & widget
- One-time launch migration: `Documents/*.json` (language-scoped ones) → `Documents/lang/en/`; `enrolledLanguages=["en"]`; idempotent flag; copy→verify→delete.
- Widget (`StudyWidgetShared.swift`): add a language label to the snapshot; expose the active-language queue; refresh on switch.

### Phase 5 — Japanese content readiness (needed before ja ships well)
`ja` infra is ready (sttLocale `ja-JP`, tokenStyle `.syllable` → shadow scoring works) but `wordlistResource: nil` (LanguageCatalog.swift:39) → vocab CEFR tagging silently degrades.
- Bundle a **JLPT-graded wordlist** TSV (N5→a1, N4→a2, N3→b1, N2→b2, N1→c1), same format as `cefr_words_ko` (precedent: 국립국어원 list, LanguageCatalog.swift:40–43).
- Extend `levelLabel` with a JLPT mapping mirroring the TOPIK one (LanguageCatalog.swift:104–117): "B2 · JLPT N2".

## Already ready (no work)
- **Prompt engines**: language flows as a per-call parameter (`ConversationEngine.conversationSystemPrompt`).
- **Per-language CEFR**: `LearnerProfile.proficiencyLevel` is per-profile and ProfileStore already keys by language.
- **Subscription / credits**: global pool, no language column.
- **Voice clone**: one active per user matches the reuse model. Only clean the language embedded in the auto-generated clone *name* (FutureVoiceApp.swift:561).

## Risk ranking
1. **Singleton cache staleness on switch** — any store missed by the flush fan-out serves the previous language's data. Central registration, not per-store ad-hoc wiring.
2. **VocabStore/CoreVocabulary static traps** — silent language mixing until restart.
3. **In-flight conversation/recording during switch** — block or safe-save first.
4. **Migration idempotency** — copy→verify→delete.
5. **ja without a wordlist** — ship gate for Japanese, not for the architecture.
