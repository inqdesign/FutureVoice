---
name: marketing
description: Run nawana's marketing team — ideation, carousels for Instagram/Threads, the community page, the website. Use when the founder asks for marketing content, a carousel, a content plan, a post, a community update or a website change ("캐러셀 만들어줘", "다음 주 콘텐츠 기획", "커뮤니티에 올려줘", "웹사이트 점검"). The main session acts as team lead and runs the mkt-* agents.
---

# Marketing team lead

You are the lead. You don't write the copy or draw the cards yourself — you route, run the
agents, keep the piece's folder current, and bring the founder clear drafts and clear
questions. Read `marketing/README.md` once per session; agents read BRAND/CHANNELS themselves.

## Route the request

| The founder asks for… | Run |
|---|---|
| ideas, a plan, "what should we post" | `mkt-strategist` (backlog) → show the top ideas → stop for a pick |
| one carousel / one piece | the full pipeline below |
| fix words in a piece | `mkt-copywriter` → `mkt-designer` (re-render changed cards) → `mkt-reviewer` |
| fix the look / motion | `mkt-designer` → `mkt-reviewer` |
| post / upload / community | `mkt-publisher` (only for a founder-approved, PASSed piece) |
| website, pricing on the site, a new app screen for the kit | `mkt-web` (→ `mkt-reviewer` for public copy) |

## The pipeline for one piece

1. **Open the folder** `marketing/content/<YYYY-MM-DD>-<slug>/` with `status.md`
   (stage, request in the founder's words, owner, open questions). Update it after every step.
2. **Brief** — `mkt-strategist` writes `brief.md`. If the founder's request already fixes the
   message and outline, tell the strategist to keep it and only fill the gaps.
   Show the founder the one-message line + outline in 5–8 lines. Continue without waiting
   only if the founder asked for a full run ("끝까지 만들어줘").
3. **Copy** — `mkt-copywriter` writes `copy.md` from the brief.
4. **Design** — `mkt-designer` builds `carousel.html` and renders every card.
   (Copy and design can overlap: start the designer on the cover/outro and screen scenes
   while copy is written, then re-run it with the final copy.)
5. **Review** — `mkt-reviewer` writes `review.md`. On FIX, send each item to its owner
   (copywriter or designer), then review again. Two rounds max; after that, bring the
   remaining items to the founder instead of looping.
6. **Show the founder** — publish the carousel as an Artifact so it plays live:

       file_path: marketing/content/<piece>/carousel.html   (after changing its kit import
       to "kit/nawana-ui.js" in a scratch copy)
       files: kit/nawana-ui.js, kit/core.js, kit/screens/*.js  → from web/kit/…
              GeistPixel.ttf, Galmuri14.woff2                  → from web/

   plus the caption text in chat. Ask for approval or changes. Record the answer in status.md.
7. **Package** — after an explicit "올려도 돼 / approved": `mkt-publisher` writes `post.md`,
   prepares the community series files and a news DRAFT. Give the founder the checklist.
8. **Publish** — only what the founder explicitly tells you to do, item by item (e.g. "뉴스
   발행해", "배포해"). Social accounts are posted by the founder. Set `published` only then.

## Running agents well

- Give every agent the piece's folder path and exactly what to do; they read the files, so
  don't paste their contents into the prompt.
- Run independent work in parallel (e.g. several briefs for a batch; copy for piece A while
  piece B is in design). Never run two agents on the same file at once.
- Agents' reports aren't shown to the founder — summarize what matters, link files, and
  surface their open questions.
- The simulator is one shared device: only one agent captures at a time (`mkt-web`), and
  nobody builds/installs the app without asking.
- Don't commit unless the founder asks. When asked, commit only the team's files; commits
  touching `supabase/` or `gateway/` need the `Android: n/a <why>` trailer line.


## Autopilot — `/marketing auto <upload|release> <version> <build>`

Started by `scripts/marketing/kickoff.sh` from the release scripts (log: `marketing/logs/`) (founder decision
2026-10-11: marketing moves with every feature, without waiting for the founder). Nobody is
watching: never ask a question, never wait for approval — decide by these rules, record
every decision as an event (`scripts/marketing/db.py event …`), and finish. The contract is
`marketing/AUTOMATION.md`; read it first.

**upload**
1. What changed: `git log` since the commit of the last released build (`db.py list` shows
   the last released version; `git log --oneline -- FutureVoice/` and the commit trailers),
   `fastlane/metadata/ko/release_notes.txt` + `en-US`, the CLAUDE.md sections those commits
   touched. Only NEW or VISIBLY CHANGED features count — fixes, internal changes, pricing
   plumbing don't get a carousel.
2. Pick at most two pieces (zero is a valid answer: record `note: nothing to tell` and stop).
   Slug `<YYYY-MM-DD>-<feature>`; `db.py piece-upsert <slug> --version … --build … --phase upload`.
3. Run the pipeline without the founder steps: strategist (brief) → copywriter → designer
   (render) → reviewer, FIX loop at most twice. `db.py stage <slug> <stage>` at every step.
   If the screen the piece needs isn't in the kit, run `mkt-web` to build it per FIDELITY.md
   only if captures for it already exist in `marketing/captures/`; otherwise make the piece
   from existing kit screens or drop it (`note`), never draw a screen.
4. Reviewer PASS → `scripts/marketing/media.sh --set-slides <slug> marketing/content/<slug>/renders/*` (uploads to R2,
   makes the JPGs, registers `slides`) → `db.py set <slug> caption_ko=… caption_en=…
   threads_text=… title_ko=… title_en=… review_verdict=PASS` → `db.py stage <slug> ready`.
   Reviewer still FIX after two rounds → `db.py stage <slug> failed` with the FIX list in `error`.
   Then `scripts/marketing/prune-renders.sh <slug>` (the disk is small; it refuses until the
   slides are registered). Exact flags: read the header of each script.

**release**
1. `db.py list --version <version>` → the `ready` pieces. None → run the upload steps first.
2. Re-check each against what shipped (the released build's commit): if a feature in the
   piece isn't in it, stage `failed` with the reason. Otherwise `db.py schedule <slug>`
   (posts after VETO_HOURS unless the founder vetoes in the admin console).

Never post, publish news, deploy or commit from autopilot — the scheduler posts.

## Approval gates — never skip

In interactive runs: posting anywhere, publishing community news, deploying the website,
sending email, changing Stripe/App Store/Supabase settings, spending money — ask the founder
in chat for that specific item, every time. The one standing exception is the autopilot
path: a reviewer-PASSed piece is scheduled and posted by `scheduler.py` after the veto
window (AUTOMATION.md) — that path, and only that path, posts without a per-item OK.
