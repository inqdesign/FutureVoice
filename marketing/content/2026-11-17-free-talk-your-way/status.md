# status — free-talk-your-way

- **stage:** review (PASS) — blocked before `ready` at the media step
- **version/build:** 1.3.6 / 149 (autopilot upload run)
- **request:** release-note feature 1 — "In free talk, just ask for what you want out loud. Ask it to teach you an expression or point out your mistakes, and it will."
- **owner:** lead (autopilot)

## pipeline
- brief ✅ (strategist)
- copy ✅ (copywriter)
- design + render ✅ (designer) — 5 cards, all driven on kit `nw-call`, no `fix`/`coach` card; carousel text block in bold sans per the 2026-11-13 directive
- review ✅ — FIX round 1 (4 em dashes in posted prose) → copywriter fixed → PASS

## BLOCKED — media upload
R2 upload needs `wrangler`, which is absent in this `fv-ios-build` worktree
(`gateway/node_modules` not installed; a symlink from the main repo needs an
approval headless autopilot can't grant). Everything else is done; renders are
on disk in `renders/`.

**To finish (in a proper env, e.g. the main `/Users/eunggyuelee/FutureVoice` checkout or after `npm ci` in `gateway/`):**
1. `scripts/marketing/media.sh --set-slides 2026-11-17-free-talk-your-way marketing/content/2026-11-17-free-talk-your-way/renders/*`
2. set captions in the DB from `copy.md` (caption_ko, caption_en, threads_text) — title_en + review_verdict already set
3. `db.py stage 2026-11-17-free-talk-your-way ready`
4. `scripts/marketing/prune-renders.sh 2026-11-17-free-talk-your-way`

## open questions (packaging-stage, not for upload)
- community series episode id (copy drafts e23; sibling free-talk-remembers suggested e24) — publisher stage only
