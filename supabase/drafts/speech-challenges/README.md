# Speech challenges waiting their turn

Each file is one challenge (en), ready to run. To publish one, copy it into
`supabase/migrations/` with today's timestamp and apply it with
`scripts/apply-migration.sh`. They are kept out of `migrations/` so that a
`db push` can't put them all on the board at once.

A real speech goes up in its real words. Public domain ones are free (Lincoln
1863, Roosevelt 1910, a US president's speech as a federal work). One still
under copyright goes up as text only, with attribution, and is retired if the
rights holder asks (founder, 2026-11-04, Michelle Yeoh). The rest are written
for nawana.


The show-host series (07-12) is what the founder wants more of: be the
host selling one thing live. A famous speech goes up only in its REAL words.
11, 13 and 14 are the skincare set. One challenge goes up at a time, never a batch (founder, 2026-10-30).

Every challenge carries an INTRO in all eight app languages (what it is,
what to keep in mind: "you are the show host…"), set with `intro` jsonb.
