# The tutor's curriculum — chapters and topics

Founder's ask (2026-10-28): "the tutor has its own curriculum — chapters,
and topics inside them. The learner finishes one, it is checked off, and
going through all of it can be their goal." This document is the overview
and the roadmap. Nothing here is built yet; the code and CLAUDE.md are the
truth once each part ships.

## What exists today

- **Tutor mode** (`TutorLesson.swift`, `ConversationEngine.tutorBlock`): a
  topic becomes a lesson of 3–4 challenges, each said until it is clean,
  ticked by the app. A finished lesson asks "more of this, or another
  topic?"; "more" plans a next round, a step further.
- **Where topics come from**: the call's own topic, something the learner
  says, or the 💡 sheet (`TutorTopicSheet`), which lists the Talk tab's 24
  ready-made situations (`StarterSituation`, grouped by purpose) plus the
  learner's own scenarios.
- **What is kept**: the last 30 lessons on this phone
  (`tutor_lessons.json`), unsynced. Nothing says "this topic is done", and
  there is no list to fill in.

The gap: the tutor can teach any topic, but there is no map of WHICH
topics, no record of what was covered, and no next step. Every call starts
from "what do you want to practice?".

## The shape: two tiers

```
Chapter  (≈10)    Café & food
  Topic  (≈10 each)   Ordering at a café        ✓ done · round 2
                      Your order came out wrong  ✓ done
                      Asking what's good here    ← next
                      Splitting the bill         ○
                      …
```

- **Chapter** — an area of life the learner will need to speak in
  (meeting people, café and food, travel, work…). It shows `N of M topics`.
- **Topic** — one concrete thing to be able to say, small enough for one
  lesson ("your order came out wrong", not "restaurants"). A topic is what
  the planner gets, exactly as a picked topic is today.
- **Done** = one lesson on that topic finished 4/4. It is the check we
  already have; no new judgment.
- **Depth** = every further round on the same topic ("more"), shown as a
  small count beside the tick. It never gates anything; it is a record.

## The catalog

Written once by us, not generated per learner, so everyone sees the same
map and it can be checked by hand. Per topic:

| Field | What it is |
|---|---|
| `id` | stable, never reused (`cafe.order-wrong`) |
| `chapter` | the chapter id |
| `title` | the row, in every app language — written, not translated |
| `brief` | one English line for the planner: the situation and what "able to say it" means |
| `levels` | the bands it suits (`a1…c2`); the planner's level ladder still decides how hard each challenge is |
| `starterId` | optional link to a `StarterSituation`, so the topic and the Talk tab's situation are one thing |

The planner already adapts any topic to the level (`TutorPlanner.levelLadder`:
at B1+ "ordering" becomes what goes wrong around ordering), so one topic
serves every level; `levels` only decides which topics are SHOWN first.

### First draft: 10 chapters × 10 topics (for the founder to edit)

1. **Meeting people** — introducing yourself · where you're from and why
   you're here · what you do · your family · hobbies · asking someone about
   themselves · keeping a first conversation going · making plans to meet
   again · remembering and using names · saying goodbye naturally
2. **Café & food** — ordering at a café · ordering at a restaurant · asking
   what's good · allergies and special requests · your order came out wrong
   · something is sold out · paying and splitting the bill · booking a
   table · talking about food you like · complimenting the food
3. **Shopping** — asking for a size or color · trying things on · asking
   the price and paying · returning something · asking for a discount ·
   at the supermarket · at the pharmacy · buying a phone plan · ordering
   online went wrong · comparing two options
4. **Getting around** — asking the way · buying a ticket · taking a taxi ·
   a delayed or cancelled train · at the airport check-in · lost luggage ·
   renting a car · checking in at a hotel · a problem with the room ·
   giving directions to someone
5. **Home & neighbors** — calling the landlord · something is broken ·
   talking to a neighbor · a noise complaint · moving in · setting up
   internet · a delivery that didn't arrive · at the town hall · opening a
   bank account · recycling and house rules
6. **Health** — booking a doctor's appointment · describing symptoms · at
   the pharmacy · explaining an allergy · an emergency call · at the dentist
   · talking about how you feel · calling in sick · a check-up · helping
   someone who is unwell
7. **Work** — small talk with a coworker · your project update · giving your
   view in a meeting · asking for help · disagreeing politely · a call with
   a client · explaining a delay · saying no to extra work · a
   performance review · leaving a voicemail
8. **Job interview** — tell me about yourself · why this job · strengths
   and weaknesses · a project you're proud of · a conflict you handled ·
   where you see yourself · talking about salary · questions for them ·
   explaining a gap · following up after
9. **Opinions & stories** — telling what happened this weekend · a funny
   story · describing a film or book · giving your opinion · agreeing and
   disagreeing · comparing life in two countries · a decision you made ·
   plans and dreams · reacting to news · explaining something you know well
10. **Family & school** — your child's teacher · a school event · arranging
    a playdate · talking about your kids · a parent-teacher meeting ·
    calling the school about an absence · at the kindergarten pick-up ·
    asking another parent for help · birthdays and invitations · a family
    visit

This draft fills ~100 rows. 1,000 is a content project for later; the
shape doesn't change with the count.

## Unlocking

Recommendation: **soft unlocking — guide, never wall.** The app's rule is
that a learner is never blocked from practicing what they need (a job
interview tomorrow can't wait for chapter 7 to open).

- Every chapter is open from day one.
- Inside a chapter, the topics that fit the learner's level are lit and
  ordered; the rest are shown dimmed with a lock glyph and "Recommended
  after: …", but a tap still starts them (with one line: "This one is a
  step up — want to try it?").
- **Next** is always one topic: the first lit, not-done topic in the
  chapter the learner was last in, else the chapter that fits their
  purposes (`LearningPurpose`), else Meeting people.

The alternative — hard locks, finish topic N to open N+1 — makes a
stronger "progress" feeling but contradicts free practice. If the founder
wants it, it is one rule in the same place.

## Where it shows

- **Tutor mode's 💡 sheet becomes the map** — chapters as sections, topics
  with ticks and depth, "Next" pinned on top, and "Your own" (the learner's
  made-up topics, kept but not counted toward the map's total).
- **The tutor proposes the next topic.** After a finished lesson, "another
  topic" gets one concrete suggestion from the map ("next up in Café &
  food: your order came out wrong — want that?") instead of an open
  question. A learner who opens tutor mode with no topic gets the same.
- **A topic said out loud is matched to the map** when it is one of
  ours ("I want to practice ordering coffee" → `cafe.order`), so free
  requests still fill the map. Unmatched requests go under "Your own".
- **Progress**: one line per chapter later (N of M), not in phase 1.

## Data

- `TutorCurriculum` (catalog, bundled, per app language titles).
- `TutorProgress` — per target language: `topicId → { doneAt, rounds,
  lessonIds }`. Small, user-owned, worth having on every device, so it
  syncs as its own kind (union of done topics, max of rounds).
- `TutorLesson` gains an optional `topicId`, set when the lesson came from
  the map or matched to it. Finishing such a lesson writes `TutorProgress`.
- Telemetry: `tutor_topic_started` (topicId, source: map / next / voice /
  own), `tutor_topic_done` (topicId, round). That is how we learn which
  topics people actually want.

## Roadmap

| Phase | What | Done when |
|---|---|---|
| **0. Content** | Founder edits the 10 × 10 draft above; we write titles in every app language (written, not translated) and a `brief` per topic | Founder signs off the list |
| **1. Map + done** | Catalog in code, `TutorProgress`, the 💡 sheet becomes the map, lessons from the map carry `topicId`, finishing ticks the topic, depth counted | Pick a topic on the map → finish 4/4 → it's ticked, survives relaunch |
| **2. Next + proposals** | "Next" topic, the tutor proposes it after a lesson and at the start of a topic-less tutor call, spoken requests matched to the map | A tutor call with no topic offers one concrete next topic |
| **3. Soft unlocking** | Level-fitted topics lit, the rest dimmed with "a step up", ordering inside chapters | A1 and C1 learners see different "Next" in the same chapter |
| **4. Everywhere** | Sync kind, Android port (same catalog, same rules), chapter counts on Progress, map progress in the weekly report | Phone and tablet show the same ticks; Android matches |
| **5. Grow** | More topics per chapter (toward hundreds), level-specific topics at C1+, topics from what learners ask for most (`tutor_topic_started` source = own) | Driven by data from phases 1–4 |

Phases 1–2 are the product; 3 is polish; 4 is required before it is "done"
under the Android rule; 5 is ongoing.

## Open questions for the founder

1. Soft unlocking (recommended) or hard locks?
2. Is "done" one finished lesson, or should a topic need two rounds?
3. Should the Talk tab's ready-made situations and the map be ONE list
   (a starter situation = a topic), or stay separate?
4. Does the map belong only to tutor mode, or also on the Talk tab as
   "Your curriculum"?
