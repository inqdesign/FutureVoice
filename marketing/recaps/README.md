# Monthly community recap

Founder, 2026-11-14: "매월마다 이걸 하면 좋겠어." The first one is
`content/2026-11-13-together-so-far/`. It was shared in the users' group chat as the
nine stills, `video.mp4` and a PDF. Copy that folder for each new month and change
only the numbers and the lines that depend on them.

- **When:** around the 12th of each month (launch was 2026-09-12). The header counts
  months: "9월 12일부터 석 달간", "넉 달간", and so on.
- **Window:** cumulative from 2026-09-12. One card may add "this month" (call hours
  for the month, from the by-month line). Nothing new is required.
- **Audience:** current users in the group chat first. Every card has to work as a
  still image in a chat and be fit for the public.

## Rules (founder's, all from the first one)

- Only TOTALS are real numbers: call hours, calls, turns ("more than N" when it is a
  floor). Everything else is a percentage. Never a count of people, and never one
  person's figure.
- Android is included in every PostHog number (see the filter below).
- Weekday and hour are the learner's LOCAL time, never UTC.
- Show a "NEW" tag on a feature that shipped since the last recap.
- No pixel font. Geist regular (`web/creators/fonts/geist.woff2`) at weight 600.
  There is a nawana footer on every card except the cover and the thanks card.
- The thank-you card is 해요체 with 높임 ("함께해 주셔서 고마워요"). The group chat
  message is 합니다체. See the last recap's `copy.md`.

## Steps

1. `cp -R content/<last recap> content/<YYYY-MM-DD>-together-<n>-months`, then delete
   `renders/`, `video/`, `video.mp4` and `*.pdf` in the copy.
2. Numbers:
   - Server half: `marketing/recaps/supabase.sh` (read-only; `SINCE` / `UNTIL` args).
   - PostHog half: the queries in `posthog.md`, run through the PostHog MCP.
   - Write both into the new folder's `data.md`, with the window and the date pulled.
3. Change the numbers in `carousel.html` and `copy.md`. The data lives in `data-rows`
   attributes (cards 7 and 8), `WEEK` (card 5), the share bar flex values and the
   country list (card 3), and the language bars (card 6).
4. Render the stills, one card at a time (`?solo=N`). Then the clips (`?solo=N&anim=1`),
   recorded ONE AT A TIME (parallel recording drops frames). Then join with 0.4 s fades
   and build the PDF. The commands are below.
5. Send it to `mkt-reviewer`. Show the founder. Nothing goes out without their OK.

```bash
P=marketing/content/<piece>; N=/opt/homebrew/opt/node@22/bin/node
for n in 1 2 3 4 5 6 7 8 9; do
  $N scripts/marketing/record.mjs "$P/carousel.html?solo=$n" --seconds 2 --out $P/renders/0$n.png
done
lens=(7 8 10 8 9 9 10 11 7)
for n in 1 2 3 4 5 6 7 8 9; do
  $N scripts/marketing/record.mjs "$P/carousel.html?solo=$n&anim=1" --seconds ${lens[$((n-1))]} \
    --warmup 0 --wait-for "document.documentElement.dataset.ready" --out $P/video/0$n.mp4
done
# join: ffmpeg xfade, 0.4 s, offset += len[i-1] - 0.4 (do it in Python; a zsh loop
# left the offset empty). PDF: PIL Image.save(..., save_all=True) over renders/*.png.
```

## Pitfalls hit the first time

- PostHog `$app_namespace LIKE 'com.roro.futurevoice%'` drops ALL of Android. Android
  sends `platform = android` and no namespace.
- Android has `$geoip_time_zone` and no `$timezone`. `toTimeZone` needs a constant zone,
  so map zones with `multiIf`.
- Shadowing: `client_events` only starts on 2026-09-16, so take the union with the
  ledger's purpose `shadow`. Counting only one source gave 32% instead of 46%.
- "Pronunciation" in the ledger counts takes scored in the background. That is not a
  feature someone chose, so leave it out. A pronunciation CALL is `mode = pron`.
- Hong Kong is a region, not a country. If it is in the count, say "N개 나라와 지역",
  or leave it out of the number.
- An English set goes beside the Korean one: `carousel-en.html` (English copy written as English,
  never translated; at the end of `copy.md`), `renders-en/`, `video-en/`, `video-en.mp4`, `cards-en.pdf`.
- "둘 중 한 명꼴" needs ≥50%. For 43–49% say "거의 절반".
