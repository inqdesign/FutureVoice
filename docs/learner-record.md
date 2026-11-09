# The Learner Record

Founder, 2026-11-09: one well-curated, documented, constantly updated source
of truth per learner, for the tutor and for every other piece of content.
What a learner actually said, and the audio, stays on the phone. That does
not mean the server knows nothing about them.

Status: **tables applied, upload built on iOS and Android, switched off**
(`billing_config.learner_record_on`). It extends parts 2 to 4 of
`docs/personal-report-plan.md`. Once a part ships, the code and CLAUDE.md are
the truth.

## The problem

Learning data lives in more than 30 files on the phone, and each feature
reads a few of them.

- The tutor chat assembles its own picture for each prompt
  (`TutorChat.context`). It is the closest thing to a record, and only the
  chat uses it. It cannot see pronunciation, lesson history or the future
  goals from onboarding.
- The lesson planner gets the topic, level, job and city. It has never seen
  the learner's mistakes.
- The student file (`learner_state.json`) is read only by the chat, is built
  from talks only, and exists only for English (32% of recent learners study
  something else).
- Nothing leaves the phone, so "does this mistake shrink after a lesson?"
  cannot be measured, a reinstall loses everything unless iCloud sync was on,
  and iOS and Android can't share one picture.

## The rule

**The content of conversations stays on the phone. Everything else about the
learner is fair to know if it makes the service better** (founder,
2026-11-09: whether someone knows "milk" or studied it is not private).

The line is one question: can this be used to read what they said in a call?

| Stays on the phone | May go to the server |
|---|---|
| Audio, recordings, the voice sample | Languages, level, level history |
| Transcripts and any quote of the learner's words | Results per grammar and speaking item |
| Text taken from a call: sentence cards, corrections, shadow lines | Words and expressions with their state |
| Facts distilled from calls (`learnedNotes`) | Scores per sound |
| Tutor chat | Results of lessons, tests, shadowing |
| Attached files, read in place by design (`brief`) | Profile typed in setup, purposes, goals |
| | Routine and minutes per activity |

Prompts are built on the phone, so nothing is lost: the phone combines the
server record with what only it knows, every time it writes a prompt.

## Shape

```
phone: raw files (unchanged, and the sync engine unchanged)
   │  after each activity: small result events, no text from the learner
   ▼
server: learner_events  (one row per fact, replaced by key)
   │  computed by one server function
   ▼
server: learner_record  (one JSON per learner and language)
   │  fetched, cached on the phone
   ▼
phone: LearnerRecord view + local private details ──► prompts and picks
```

### `learner_events`

| Column | Notes |
|---|---|
| `user_id` | `references auth.users on delete cascade`, so `account-delete` removes it |
| `key` | Built by the client, unique per user. Example: `talk:<sessionId>:item:past_simple` |
| `language` | Target language |
| `occurred_at` | When it happened, not when it arrived |
| `source_id` | The talk, lesson or test it came from, for deletion |
| `kind` | From the allowlist below |
| `subject` | Map item id, lemma, phoneme, topic id. At most 60 characters |
| `value` | Small JSON, numbers and fixed strings only |
| `platform`, `app_version` | For debugging |

- **Written only through one RPC** (`learner_events_put(batch)`). It rejects
  an unknown kind, a value key not on that kind's list, a long `subject` and
  an oversized batch. This is the guard that stops a sentence reaching the
  table, whatever a future build tries to send.
- **Replaced by key, never counted twice.** The same rule as `LearnerState`
  ("stored per talk, read per item"). A talk re-tagged later replaces its own
  rows, and two devices sending the same talk produce one set.
- **A deleted talk takes its rows with it** (`learner_events_forget(source_id)`).
- RLS: the owner reads their own rows. No client writes outside the RPC.
- **Only for a real account.** Never from an anonymous session, the same
  rule as sync.
- **Offline:** events queue on the phone and go later. Nothing waits on them.

### `learner_record`

One row per user and language: `body jsonb`, `computed_at`, `schema_version`.
One server function computes it, so iOS and Android can't disagree about
what a status means. The status rule now in `LearnerState.status` moves there.

The phone caches the last body. A call never waits for the server.

## Events (the allowlist)

| Kind | Subject | Value | Source today | When |
|---|---|---|---|---|
| `setup` | field name | fixed id or short typed value | `profiles`, purposes, `occupation`, `city`, `interests`, `goals` | On change |
| `goal` | goal id | kind, date, title, place, notes | `UpcomingGoal` (no `brief`) | On change |
| `talk` | session id | minutes, mode, learner words, turn count, wpm, pauses, axis scores, CEFR read, grammar range | `Session`, `ScorecardMetrics`, `SessionScorecard` | Talk summarized |
| `item` | map item id | right, wrong | `LearnerState.ItemTag`, quotes removed | Talk tagged |
| `word` | lemma | studying, known, used, count | `VocabStore` | On change |
| `expression` | phrase, 6 words at most | studying, known, used, count | `VocabStore`, `ExpressionCatalog` | On change |
| `card` | card id | box, seen, correct, used at | `DrillCard`, no text | On review |
| `shadow` | turn id | overall, match, rhythm, partial | `ShadowAttempt`, no text | Take scored |
| `sound` | phoneme | score, samples, surface | `PronunciationEntry.phonemes` | Take assessed |
| `lesson` | topic id or `custom` | challenges, tries, done, check passed | `TutorLesson`, `TutorTopicProgress`, no title | Lesson ends |
| `test` | item kind | right, appealed, score | `WeeklyTestAnswer`, no `given` | Test ends |
| `day` | date | minutes and reps per activity | `TalkTimeLog`, `PracticeLog.Day`, `ActivityEventLog` | Day's first event, then on change |
| `routine` | block kind | weekday, time, amount, promise kept | `StudyPlan`, `PromiseLedger` | On change |

Two kinds are deliberately missing until they are read:

- **Recurring mistakes.** `mistake` and `correction` quote the learner, so
  they stay. `context` is model-written English and looks safe, but it may
  echo their words. Read a real sample before allowing it.
- **Talk titles.** A title can say what the talk was about, which is what
  was said.

## The record (what readers get)

| Section | Contents |
|---|---|
| `who` | Languages, level and how it was set, purposes, job, city, interests |
| `why` | Future goals, upcoming goals with days left |
| `standing` | Grammar and function items with status, per-skill bands |
| `weak` | Shaky items, weak sounds, words studied and never used |
| `recent` | Last 14 days per activity, last lessons and results |
| `habit` | Routine, streak, what they use and never use |
| `focus` | The current focus (below) |

`focus` is the one thing that is decided, not computed. It says what this
learner is working on now and why, and it is what the daily note, the next
lesson and the review deal all follow. Its design waits for a mockup.

## Readers

| Reader | Sections | Adds on the phone |
|---|---|---|
| Tutor chat | All | Life notes, quotes, last talks |
| Lesson planner | `why`, `weak`, `standing` | |
| Curriculum `next` | `who`, `why`, `standing` | |
| Daily note | `why`, `habit`, `focus` | |
| Call prompt | `weak`, `focus`, short | Today's existing persona block |
| Daily call script | `recent`, `who` | Last talk's phrases |
| Podcast and news picks | `who`, `why` | Can run with the app closed |
| Weekly report | All | Quotes |
| Founder's measures | `learner_events` | |

**Strangers and cast characters never read it.** A cast prompt keeps
`strangerLines` and nothing more.

## What must change first

The promise is one sentence (founder, 2026-11-09): **모든 대화의 내용은 폰에
저장합니다.** (All conversation content is stored on the phone.) The shipped
sentences below say more than that, and this one replaces them.

| Where | Today | Problem |
|---|---|---|
| `LocalDataOnboardingView` (iOS, Android, every language) | "Your practice stays on your phone" | False for progress |
| Same | "Calls, recordings and every word you study are saved right here." | False for words |
| Same | "It goes with the app: delete the app or change phones, and it's gone too." | False for progress |
| Same | "Not on our servers: we don't keep your talks, so speak freely." | Still true |
| `web/privacy.html`, `privacy-ko.html` line 51 | "Sessions, transcripts, drill cards, vocabulary, and progress are stored on your device, not on our servers." | False for vocabulary and progress |
| Same, line 111 | "Learning data ... disappears when you delete the app." | False for progress |
| App Store privacy labels, Play Data Safety | Declared without this data | Must add it |

No switch and no notice to learners (founder, 2026-11-09).

## Order of work

1. ✅ Fix the student file (2026-11-09, iOS 8c45517b, Android 4e6ac9a3).
2. Founder approves this document and the event list.
3. The one sentence replaces the old wording.
4. Migration and RPC, server only and additive. Behind a server switch that
   defaults to off, so builds can ship dark. A contract file listing every
   kind, shared by iOS, Android and the RPC, with golden vectors.
5. Client events on iOS and Android, new activity only. Then a one-time
   upload of history.
6. `learner_record` function and the phone's cached view.
7. First reader: the tutor chat. Then the lesson planner, curriculum and
   daily note.
8. `focus` (mockup first).
9. Level maps for the other languages.

## Open questions

- Row volume per learner is estimated, not measured. Measure on the first
  learners before opening it to everyone.
- A lesson must name its map item to measure "the mistake shrank". The
  planner does not output one today.
- Non-English learners get no `item` events until step 9. Every other kind
  works for them.
- The 2026-11-09 student file fix is not yet in any shipped build, and its
  effect is unmeasured on real talks. Read `level_tagged` and
  `level_tag_failed` after the next release.
