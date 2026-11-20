# Data for this piece (pulled 2026-11-13 by the lead)

Source: production `usage_ledger` (action `talk_time`), `client_events`, PostHog
(`conversation_started`, nawana namespace only). Founder and test accounts excluded.
Window: 2026-09-01 (first metered call on file) to 2026-11-13.

## Founder's rule for numbers

- TOTALS may be real numbers: total call hours (and similar whole-community totals).
- Everything else is a PERCENTAGE or a plain-word share. Never a count of people,
  subscribers, signups, or anything that reveals how many users there are.
- Never anything about one person (no "the top learner talked N hours").

## Totals (real numbers allowed)

| Fact | Value | How solid |
|---|---|---|
| Total call time with the fluent self | **85.5 hours** (say "85 hours") | solid, metered by the server |
| Calls made | about 2,000 | solid (distinct call sessions) |
| Turns spoken by learners in calls | about 14,000 | solid, but only calls that reported a session record, so "more than 14,000" |
| Shadowing takes | about 1,200 | solid ("more than 1,200") |
| Countries learners call from | 24 | solid (PostHog geo, one call or more) |
| Time in the app overall | ~750 hours | ESTIMATE only (first to last event per app session, includes onboarding). Do not use as a headline; use only if the founder asks, worded "roughly" |

## Shares (percentages only)

- Language practised, by call time: English 74% · German 21% · Japanese 3% · Korean 1% · Spanish under 1%.
  (French and Chinese were added on 2026-11-13, no data yet.)
- Where learners are, by people who called: Korea 43% · Germany 21% · US 10% · the remaining ~26% across 21 more countries (Australia, Canada, Japan, Singapore, UK, France, Switzerland, Austria, …).
- Came back to call on another day: 47% of everyone who ever called.
- Day of week (CORRECTED 2026-11-13): calls started, by each learner's LOCAL weekday (PostHog conversation_started + $timezone, iOS only): Mon 15% · Tue 13% · Wed 20% · Thu 16% · Fri 14% · Sat 10% · Sun 12%. Wednesday is the busiest. The line below was UTC and is WRONG (a Korean Monday morning is Sunday in UTC). OLD: Mon 18% · Tue 14% · Wed 17% · Thu 17% · Fri 15% · Sat 8% · Sun 12%. Weekdays carry 80%; Monday is the busiest day.
- Time of day (Korea, the largest group): about half of all calls start before 9 am or after 8 pm. German learners show the same two peaks (7–8 am, 8–9 pm). Say it in words ("before work, and before bed"), not a precise percentage.
- Beyond the call, among people who called: 46% also did shadowing (corrected: client_events shadow events only start 2026-09-16; the ledger purpose "shadow" covers the earlier takes) · 26% watched a scene · 14% took a tutor lesson · 12% did Say it again . (NOT usable: 12% 'pronunciation' counts takes scored in the background, not a feature someone chose.)
- FEATURE LIST (founder asked 2026-11-13 for "the list of features people are using"), share of
  people who called that have tried each at least once, Sep 1 to Nov 13:
  shadowing 46% · word & expression cards 28% · Watch scenes 26% · weekly report 23% ·
  answered the daily call 21% · weekly test 17% · asked the tutor bot 15% · tutor lesson 14% ·
  Say it again 12% · listening (podcast) 10% · speech 7%.
  Sources: shadowing, tutor lesson, Say it again from client_events; scenes from usage_ledger
  (a scene actually played); the rest from PostHog events of the same callers. Leave out widget
  and quick quiz (5%, too small) and pronunciation (background scoring, not a choice).
- CALL TYPES (founder 2026-11-13: "there is no feature list in call"), share of people who
  called that have tried each kind of call at least once (PostHog conversation_started origin /
  coach property; tutor from client_events tutor_lesson_started; daily call from
  daily_call_answered; pronunciation call from usage_ledger mode=pron):
  free talk 98% · coach mode on 43% · scenario talk 25% · answered the daily call 21% ·
  news talk 19% · tutor mode 14% · pronunciation call 4% (launched Nov 4, so low).
  Daily call and tutor move to this list and OUT of the beyond-the-call list.
- Month over month: October's call time was 2.8x September's. (November is half a month; don't compare it.)

## Do not use

- Number of users, callers, subscribers, signups, or voice clones (191 callers etc. are for internal reference only).
- The single heaviest learner's hours or streak.
- Medians (7 min per person) or anything that makes the community look small.

## CORRECTION 2026-11-13 (founder: "why leave Android out?") — these replace the figures above

The PostHog filter `$app_namespace LIKE 'com.roro.futurevoice%'` dropped every Android event:
Android sends `platform = android` and no namespace. All PostHog figures were re-run with
`(namespace LIKE nawana OR (platform='android' AND namespace IS NULL))`, from 2026-09-12.
Supabase figures (call hours, calls, turns, languages, shadowing, scenes, tutor lessons,
Say it again, pronunciation call) always included Android.

- Countries: 26 (KR, DE, US, AU, CA, JP, SG, CM, GB, CH, FR, AT, PH, PL, ID, BR, MX, CN, HU,
  ES, LV, TR, ZA, IN, HK, SE). Shares of people: Korea 43 · Germany 22 · US 10 · 23 others 25.
- Weekday (calls started, local time; iOS $timezone, Android $geoip_time_zone):
  Mon 15 · Tue 13 · Wed 18 · Thu 19 · Fri 14 · Sat 10 · Sun 11 (largest remainder, sums 100).
  Wednesday + Thursday = 37%. Card: "주 중반이 가장 붐벼요".
- Call types: free talk 97 · coach mode 46 · scenario talk 27 · daily call 22 · news 18 ·
  tutor mode 14 · pronunciation coach 4.
- Beyond the call: shadowing 46 · word & expression cards 29 · Watch scenes 26 · weekly report 26 ·
  weekly test 18 · asking the tutor 18 · speech 13 (speech_take, speech_study_made, challenge
  entered) · Say it again 12 · listening 11.
- Turns "14,000+" is a floor: session records start 2026-09-17 and some calls lost theirs.
