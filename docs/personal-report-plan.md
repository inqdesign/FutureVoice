# The personal report and the master plan

Founder's goal (2026-10-27): nawana is the learner's own tutor — their voice,
everything we remember, every mistake we have seen. The report is where that
shows: **this is where you are, this is what holds you, this is how we take
you to the next level, follow this and we measure it next week** — narrated
by the fluent self. "The only way we win is content curated for this one
learner." This document is the plan; the code and CLAUDE.md are the truth
once each part ships.

## What exists today, and the gap

Measured and kept:

- Per talk: `SessionScorecard` (vocabulary, grammar + `grammarRange`,
  expressiveness, fluency, pronunciation when shadowed), verified fixes,
  `expressions_offered`, carryovers, `about_user` notes.
- Across talks: `LearnerProfile` (level, top recurring mistakes, weak vocab
  areas), `GrammarFocus` (one mistake with evidence in 2+ talks, retired on
  evidence), Progress's per-skill bands (`ProgressTab.grammarBand`, fluency
  band, graded vocabulary), `WeeklyReport` (pooled CEFR read, gated on
  speaking time), `WeekRecap` (the week's deck, coach note with grammar
  points, upgrades and a 2–3 line plan), the weekly test, the routine.

The gap: almost all of it is **told once and dropped**. The next call sees
only the level, three recurring mistakes ("gently aware", nothing acts on
them) and weak vocab areas. The week's coach plan is three sentences nobody
checks. Pronunciation weak words reach nothing. Nothing says "last time X,
this time Y", and nothing says where the learner is on the way to the next
level. `WeeklyReport` and `WeekRecap` are two reports that don't know about
each other.

## The design: one system, four parts

### 1. The level map — the same for every learner

A fixed list per target language of what each step needs
(`FutureVoice/Resources/LevelMap/level_map_<code>.json`, versioned):

- **grammar** — structures ("past simple, regular and irregular",
  "present perfect for experience", "first conditional"), each with the
  level it belongs to, prerequisites, a correct example and the typical
  learner error.
- **function** — what a speaker can DO at that level, from the CEFR spoken
  production/interaction can-dos written in our own words: tell a story in
  order, give a reason, compare, handle a problem, keep a conversation going.
- **vocabulary** — share of words used from each band (our graded lists).
  Computed in code.
- **fluency** — turn length, pace, native-language fallbacks. Computed in
  code.

The map is what makes the plan systematic and every piece of advice
explainable: each line traces to a map item and to the learner's own words.

### 2. Learner state — specific to each learner

Every map item carries: `unseen · tried · shaky · solid`, counts of right
and wrong uses, the dates, and up to three of the learner's own lines.
Updated after every talk by a TAGGING call (below), and by tutors, the
weekly test and shadowing. Status is computed in code from the counts —
the model only reports what it saw, never a status.

**Tagging** is its own call after the summary (`purpose: "level-tag"`,
default model, free), not a field in the summary: the summary schema's
order is load-bearing and its prompt is measured, and tagging has to be
measured on its own. Input: the learner's evidence turns (`isEvidence`) and
the talk's verified fixes; output per item seen: right uses, wrong uses,
one verbatim quote each. Every quote is checked against the learner's turns
in code; an item without a verified quote is dropped. **Accuracy is
measured before anything is built on it** (`scripts/level-tag-probe.py`).

### 3. The master plan — the gap, in order

Everything the next level needs that the learner doesn't have solid yet,
ordered mostly by code:

1. prerequisites first (past simple before present perfect),
2. shaky before unseen (closest to done),
3. pulled forward by the learner's purposes and situations (an interview
   pulls "talk about experience"),
4. the bottleneck skill first — the band that is lowest on Progress.

The model only phrases the plan in the native language and breaks ties.
The plan always shows the WHOLE path ("A2 → B1: 14 of 22") and 2–3 ACTIVE
goals for this week. `GrammarFocus` becomes one kind of active goal.

### 4. The weekly cycle — the report runs it

`WeekRecap` becomes the one report (the assessment's CEFR read folds into
it). Its order:

1. **Where you are** — level, and the skill holding it ("vocabulary is B1,
   grammar range keeps you at A2").
2. **What we found** — the 2–3 gaps, each with their own lines.
3. **Last week's goals, measured** — came up / right / right first time.
4. **The path** — the map, this week's place on it.
5. **This week's plan** — goals, and one button: put it in my routine
   (fills routine blocks with goal content: tutor lessons, pronunciation
   five, a scene that needs the structure, cards from their mistakes).

Between reports everything works on the plan: calls steer lightly toward
the active goals (what coach mode does for the grammar focus today, for
every goal and every call), tutors drill one goal, the weekly test checks
the goals, every wrap-up says one line of progress.

### The narration — the report is PRESENTED, in the learner's voice

Each card gets one or two spoken sentences; the fluent self narrates the
deck in the voice the learner picked (`speakingVoiceId`) at their speed,
the deck advances when a line ends, a tap pauses. 60–90 seconds.

- **Language: the target language, at the learner's level, with native
  captions** (founder's pick, 2026-10-27). It is listening practice and it
  keeps the fluent self fluent; the captions carry the explanation.
- The script is written FROM the numbers the code computed (same rule as
  the coach note: handed the numbers, never asked for them).
- Audio is made once per report, saved, replayed free. `PacedSpeech` gives
  the sentence gaps. ~1–2 min of speech per learner per week.
- **First home: the free-minutes report** (`TrialReport`), right before the
  plans — the moment a learner decides. Then the weekly deck.

## Honest limits (say them on screen where they apply)

- **Speaking level only** — we hear speech, not reading or writing.
- **Thin at first** — week one comes from the onboarding level and the
  first calls; it sharpens every week.
- **Levels move slowly** (A2 → B1 is months). Goals move weekly; the level
  moves when it does. No "B1 in N weeks" until real data says how fast
  learners move.
- **Promise what we control**: "follow this week's plan and we measure the
  result next week" — never "we guarantee B1".

## Order of work

1. **English level map A1→B2 + tagging prompt + accuracy probe.** The
   foundation; the probe tells us whether the plan can be trusted.
2. **Narrated free-minutes report prototype** (target language + captions),
   on `-trialdemo`, judged by ear. Independent of 1.
3. **Learner state** filled after every talk (seeded from the profile and
   the grammar focus).
4. **Master plan + the new weekly report** (bottleneck, gaps, last week
   measured, path, plan → routine), narrated.
5. **Calls, tutors and the weekly test read and write the plan.**
6. **Maps for ko, ja, de, es** — grammar differs per language, each needs
   its own map and its own probe run.
7. Android follows each step (see "Android moves WITH iOS").

## Status

| Step | State |
|---|---|
| 1. English map + probe | done 2026-10-27 — see below |
| 2. Narrated trial report | not started |
| 3–7 | not started |

### Step 1 result (2026-10-27)

`FutureVoice/Resources/LevelMap/level_map_en.json` (43 grammar items A1–B2
with prerequisites, 16 functions) and `scripts/level-tag-probe.py` over 14
hand-labelled talks (`scripts/level-tag-cases-en.json`, A1–B2, with traps:
structures only the AI used, look-alikes like "I have a car", ASR fillers).

| gemini-3.6-flash | grammar recall | exact verdict | traps | functions |
|---|---|---|---|---|
| thinking low, 3 runs | 186/204 (91%) | 183/204 | 0 | 61/81 |
| **thinking medium, 2 runs** | **131/136 (96%)** | **129/136** | **0** | **44/54** |

Use **medium**: the call runs after the talk, nobody waits. Misses are
conservative (an item left out, never invented), which is the safe side —
a miss slows a goal, a false tag would close one. "Unlabelled extras" are
real uses the labels didn't list (basics inside advanced talks), reviewed
by hand. The quote check drops fillers and stutters before matching
("I am working on a new app" from "I am uh I am working on uh a new app");
the app's verifier must do the same. The prompt lives in the probe for now;
it moves into Swift (`LevelTagger`) in step 3 and the probe will read it
from there, like `correction-probe.py`.
