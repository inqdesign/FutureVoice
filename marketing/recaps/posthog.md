# PostHog half of the monthly recap

Run these through the PostHog MCP (`execute-sql`, project 146552). Replace `SINCE`
with the window's start (`2026-09-12`). They exclude the test accounts by uppercase
distinct_id. If `admin/src/assemble.ts` gains a TEST_ID, add it here too, in uppercase.

```
-- the two filters every query uses
APP:  (properties.$app_namespace LIKE 'com.roro.futurevoice%'
       OR (toString(properties.platform)='android' AND properties.$app_namespace IS NULL))
TEST: upper(distinct_id) NOT IN ('72BCAA7E-3DD2-4364-B197-078BA59C1CE4','C7565D27-528C-46C1-9662-37248EC8AA36',
      'ECD78251-49C4-4E18-A156-6FBE90FD6E3B','C5A85F25-A631-47C5-B32B-FB5BC89C551E','5692CFC2-13EC-4F7E-A3BC-31DAEE02E28F',
      'B28CA7B1-DBD8-46DE-BFD2-5857E05665BC','4D63C941-F08C-4509-8958-7092A4357778','3CAD242A-AA84-4DCD-8F85-EF4B7262B309',
      'A52338B4-5227-400A-B6BE-E54EBAB1D53E','6082DF7E-2AE3-4B5E-9D70-5A26C3D2CD15','C283DB85-1FA2-4F91-8254-138FF291C967')
```

## 1. Countries (people who started a call)

```sql
SELECT toString(properties.$geoip_country_code) cc, uniq(distinct_id) n
FROM events WHERE event='conversation_started' AND timestamp > 'SINCE' AND APP AND TEST
GROUP BY cc ORDER BY n DESC
```
Turn this into shares (top three plus the rest) and the full list of names. Never print the counts.

## 2. Weekday, local time (calls started)

```sql
SELECT dow, count() c FROM (
  SELECT timestamp, coalesce(nullIf(toString(properties.$timezone),''), toString(properties.$geoip_time_zone)) tz,
    multiIf(tz='Asia/Seoul', toDayOfWeek(toTimeZone(timestamp,'Asia/Seoul')),
            tz='Asia/Tokyo', toDayOfWeek(toTimeZone(timestamp,'Asia/Tokyo')),
            tz IN ('Europe/Berlin','Europe/Zurich','Europe/Vienna','Europe/Paris','Europe/Stockholm','Europe/Warsaw','Europe/Budapest','Europe/Amsterdam','Europe/Madrid','Europe/Rome','Europe/Brussels'), toDayOfWeek(toTimeZone(timestamp,'Europe/Berlin')),
            tz IN ('Europe/London','Europe/Dublin'), toDayOfWeek(toTimeZone(timestamp,'Europe/London')),
            tz IN ('Asia/Singapore','Asia/Manila','Asia/Shanghai','Asia/Hong_Kong','Asia/Makassar','Asia/Kuala_Lumpur','Asia/Taipei'), toDayOfWeek(toTimeZone(timestamp,'Asia/Singapore')),
            tz IN ('Asia/Phnom_Penh','Asia/Jakarta','Asia/Bangkok'), toDayOfWeek(toTimeZone(timestamp,'Asia/Bangkok')),
            tz IN ('America/New_York','America/Toronto','America/Detroit'), toDayOfWeek(toTimeZone(timestamp,'America/New_York')),
            tz='America/Chicago', toDayOfWeek(toTimeZone(timestamp,'America/Chicago')),
            tz IN ('America/Los_Angeles','America/Vancouver'), toDayOfWeek(toTimeZone(timestamp,'America/Los_Angeles')),
            tz IN ('Australia/Brisbane','Australia/Sydney','Australia/Melbourne'), toDayOfWeek(toTimeZone(timestamp,'Australia/Sydney')),
            tz='Africa/Douala', toDayOfWeek(toTimeZone(timestamp,'Africa/Lagos')),
            tz='Europe/Istanbul', toDayOfWeek(toTimeZone(timestamp,'Europe/Istanbul')),
            toDayOfWeek(timestamp)) dow
  FROM events WHERE event='conversation_started' AND timestamp > 'SINCE' AND APP AND TEST)
GROUP BY dow ORDER BY dow
```
A new country's zone falls back to UTC. Look at the distinct `tz` values first and add any zone that is missing.

## 3. Call types and features (percent of people who started a call)

```sql
WITH base AS (SELECT upper(distinct_id) d, event, toString(properties.origin) o, toString(properties.coach) co
              FROM events WHERE timestamp > 'SINCE' AND APP AND TEST),
callers AS (SELECT DISTINCT d FROM base WHERE event='conversation_started'),
per AS (SELECT d, groupUniqArray(event) ev,
          max(event='conversation_started' AND o='free') fr, max(event='conversation_started' AND o='scenario') sc,
          max(event='conversation_started' AND o='news') nw, max(event='conversation_started' AND co='on') coach
        FROM base WHERE d IN (SELECT d FROM callers) GROUP BY d)
SELECT round(100*avg(fr)) free, round(100*avg(coach)) coach, round(100*avg(sc)) scenario, round(100*avg(nw)) news,
  round(100*countIf(has(ev,'daily_call_answered'))/count()) daily_call,
  round(100*countIf(hasAny(ev,['word_known','drill_reviewed','drill_snoozed','expression_bookmarked','word_saved']))/count()) cards,
  round(100*countIf(has(ev,'week_recap_opened'))/count()) week_report,
  round(100*countIf(has(ev,'weekly_test_started'))/count()) weekly_test,
  round(100*countIf(hasAny(ev,['tutor_bot_opened','tutor_bot_start','tutor_bot_pick','tutor_bot_asked']))/count()) tutor_bot,
  round(100*countIf(hasAny(ev,['playlist_started','podcast_started']))/count()) listening,
  round(100*countIf(hasAny(ev,['speech_take','speech_study_made','speech_challenge_entered']))/count()) speech
FROM per
```
Shadowing, scenes, tutor lessons, Say it again and the pronunciation call come from
`supabase.sh`, because the server sees them on both platforms. If a new feature
shipped, list its events first (`SELECT event, uniq(distinct_id) ... GROUP BY event`)
and add a column for it.
