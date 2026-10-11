# Channels

What goes where, at what size. The publisher packages to these; the designer renders to
these. Handles and logins are the founder's — the team never signs in or posts.

## Instagram (main)

- Carousel: up to 20 items, each a 1080×1350 (4:5) image or video. Mixing is fine: video
  for cards with motion, PNG for cover/outro. Video per item ≤ 60 s; we use 8–12 s loops,
  H.264, 30 fps (`record.mjs` output as-is).
- Caption ≤ 2,200 chars; first line is the hook (shown before “more”). 3–5 hashtags at
  the end, Korean + English mix (#영어회화 #영어공부 #스피킹 …), never 30.
- Cover (item 1) must work as a still in the grid.
- Account handle: _ask the founder_ (fill in here once known).

## Threads

- Up to 10 images/videos per post, text ≤ 500 chars. Repost the carousel's first 5–10
  items with a shorter, conversational text (not the IG caption pasted).

## Community page — nawana.app/community

- **Feature series** (the carousel archive): `web/community/series.json` + slide images
  `web/community/series/<id>-NN.jpg` at 720×900 (feed size halved). Entry fields: `id`
  (e01…), `cat` (start · talk · watch · practice · progress), `slides`, `ko`/`en`
  {`title`, `tagline`}. Board-order. Light renders only. Video slides: an MP4 next to the
  JPG (`web/community/video/`) where the page supports it.
  Adding an entry changes the live site on the next deploy → founder approval.
- **News** (`community_news` table): `python3 scripts/community.py news-add --title-ko …
  --title-en … --body-ko-file … --body-en-file …` creates a DRAFT; `news-publish <id>`
  makes it live instantly → founder approval. Release news is posted by `beta.sh`.
- Same content as social, same day: the series entry mirrors the Instagram carousel.

## Website — nawana.app

- Live root = the launch page (`web/index.html` = `launch.html`). The full pages in
  progress: `web/ko.next.html` (Korean, the design lead) and `web/index.next.html` (English).
- Live app screens come from `web/kit` (one `<script type="module" src="/kit/nawana-ui.js">`).
- Web billing (Stripe) is on in the `.next` pages; prices must match BRAND.md.
- Static hosting on Vercel (`web/vercel.json`); deploy only with founder approval.

## Formats cheat sheet

| Output | Size | From |
|---|---|---|
| IG / Threads card | 1080×1350 MP4 or PNG | `carousel.html?solo=N` → `record.mjs` |
| Community slide | 720×900 JPG | the PNG, halved (`sips -Z 900` / PIL) |
| Reel / Story | 1080×1920 | not set up yet — ask before making one |
