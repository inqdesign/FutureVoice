# status — free-talk-remembers

- **stage:** review (PASS) — blocked before `ready` at the media step
- **version/build:** 1.3.6 / 149 (autopilot upload run)
- **request:** release-note feature 2 — "Free talk now remembers past talks in much more detail. Bring up one from days ago and it finds what you actually said, then carries on from there."
- **owner:** lead (autopilot)

## pipeline
- brief ✅ (strategist)
- copy ✅ (copywriter)
- design + render ✅ (designer) — 5 cards, one scripted `nw-call` free talk at three moments; no faked memory-list/score UI; carousel text block in bold sans per the 2026-11-13 directive
- review ✅ — PASS, 0 FIX

## BLOCKED — media upload
Same blocker as the sibling piece: `wrangler` is absent in this worktree.
Renders are on disk in `renders/`.

**To finish (proper env / after `npm ci` in `gateway/`):**
1. `scripts/marketing/media.sh --set-slides 2026-11-17-free-talk-remembers marketing/content/2026-11-17-free-talk-remembers/renders/*`
2. set captions in the DB from `copy.md` — title_en + review_verdict already set
3. `db.py stage 2026-11-17-free-talk-remembers ready`
4. `scripts/marketing/prune-renders.sh 2026-11-17-free-talk-remembers`

## notes
- MP4 02–04 first frame is mid-animation (learner's bubble typing in); the PNG/JPG poster is the full payoff line, which is what image-fallback posts — fine for a loop video.

## open questions (packaging-stage, not for upload)
- community series episode id (copy drafts e06/e20; sibling free-talk-your-way suggested e23/e24) — publisher stage only
