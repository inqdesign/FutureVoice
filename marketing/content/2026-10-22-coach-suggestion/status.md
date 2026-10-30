# status

- **stage**: ready (reviewer PASS round 2; media in R2; pending release-phase scheduling)
- **owner**: lead (autopilot)
- **version/build**: 1.2.2 (117), phase upload
- **request**: Autopilot upload. Market the one new feature in build 117 — coach mode's
  "이렇게 말해 봐 / Try saying" now knows the whole call (recent 8 lines) and your own
  facts (profile + remembered notes), so the suggestion fits what you've been talking
  about and never contradicts what you already said.
- **source**: commit 6d8b4f56 `feat(coach): '이렇게 말해 봐'가 통화 흐름과 내 사실을 안다 — 최근 8줄 + 프로필·노트`
- **kit**: `nw-call` coach pose supports `coach({ line, gloss, word })`; `<u>…</u>` marks the
  learner's own fact. Capture reference: `marketing/captures/call-coach.png`.

## notes
- Pipeline: brief → copy → design (6 cards, 4 animated + cover/outro still) → review FIX×3
  (designer: em dash removed, card 04 pointer re-aimed to the underline, accent blue
  #0A84FF → #0A5CF5) → review PASS round 2.
- Caption hashtags were moved onto the CTA line (no bare `\n#`) to pass the shell arg
  validator; every word and hashtag preserved. All other copy verbatim from copy.md.

## open questions (publisher / release phase)
- Community episode id: copy drafts `e21` (e20 = in-progress accent-words piece). Confirm
  before the publisher writes the series entry.
- IG handle / bio link live? Copy uses "프로필 링크 / link in bio", no hard-coded handle.
