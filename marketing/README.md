# nawana marketing team

A team of Claude Code subagents that plans, writes, designs, checks and packages nawana's
social carousels, keeps the community page in step, and maintains the website. The
founder approves; the team never publishes on its own.

Run it from a Claude Code session in this repo:

    /marketing <what you want>          e.g. /marketing 다음 주 캐러셀 3편 기획해줘
                                             /marketing e13 "주간 테스트" 캐러셀 만들어줘
                                             /marketing 웹사이트 가격 섹션 점검해줘

The main session is the team lead (`.claude/skills/marketing/SKILL.md`): it routes the
work, runs the agents in order (or in parallel when the work allows), and brings drafts
back to the founder. Subagents can't call each other, so every hand-off goes through the
lead and through FILES in the piece's folder.

## The team (`.claude/agents/`)

| Agent | Owns | Writes |
|---|---|---|
| `mkt-strategist` | ideas, angles, the content calendar, what to say this week and why | `brief.md`, `backlog.md` |
| `mkt-copywriter` | every word: slide text, captions, community titles, ko + en | `copy.md` |
| `mkt-designer` | the carousel itself: layout, live app screens from `web/kit`, renders | `carousel.html`, `renders/` |
| `mkt-reviewer` | fact, brand and visual QA — nothing ships without its pass | `review.md` |
| `mkt-publisher` | channel packages (Instagram, Threads), community series + news drafts | `post.md`, `web/community/…` drafts |
| `mkt-web` | the website (`web/`), the UI kit (`web/kit`), screen fidelity | `web/…` |

## One piece of content = one folder

    marketing/content/<YYYY-MM-DD>-<slug>/
      status.md        stage, owner, open questions — the lead keeps it current
      brief.md         strategist: the one message, audience, outline, channels
      copy.md          copywriter: every slide's text, captions, ko + en
      carousel.html    designer: the live carousel (from templates/carousel.html)
      renders/         designer: NN.mp4 + NN.png per slide, 1080×1350
      review.md        reviewer: PASS / FIX list
      post.md          publisher: the exact upload package per channel

Stages: `idea → brief → copy → design → review → founder-approved → packaged → published`.
Only the founder moves a piece to `founder-approved` and `published`.

## Shared rules — every agent reads these first

- `marketing/BRAND.md` — voice, visual rules, facts that must stay true
- `marketing/CHANNELS.md` — formats, sizes, where each thing goes
- `CLAUDE.md` — what the app actually does (the source of truth for every claim)

## Tools

- `web/kit/` — the app's screens as live web components (`nw-call`, `nw-home`, `nw-review`,
  `nw-weeklytest`, …). Catalogue: `web/kit/index.html`. Fidelity harness: `web/kit/_harness.html`.
- `marketing/templates/carousel.html` — the carousel template (fixed text block on top, a
  live app screen below, `?solo=N` shows one card at 1080×1350 for recording).
- `scripts/marketing/record.mjs` — records any page to MP4/PNG in real Chrome:

      /opt/homebrew/opt/node@22/bin/node scripts/marketing/record.mjs \
        "marketing/content/<piece>/carousel.html?solo=2" --seconds 10 \
        --out marketing/content/<piece>/renders/02.mp4 --out marketing/content/<piece>/renders/02.png

- `scripts/feature-series/` — the older screenshot-based series renderer (`render.py`) and
  `publish-web.py` (copies a series into `web/community/series/`).
- `scripts/community.py` — community news drafts (`news-add` without `--publish` = draft).
- New app screens: capture the real app with the simulator `-capture` harness and build the
  web version per `marketing/FIDELITY.md` — never draw a screen from imagination.

## Autopilot

Every build upload starts the team and every App Store release finishes it — no founder
input (`marketing/AUTOMATION.md`). A reviewer-PASSed piece is scheduled and posts itself
after the veto window (12 h) unless the founder presses 게시 막기 in the admin console tab
마케팅, where the whole pipeline, previews and views/likes/saves are visible.

## Approval gates (hard)

Outside the autopilot path, the founder approves, in chat, each of these — every time:
posting to any social account · publishing community news or a new series entry ·
deploying the website · sending any email · anything that spends money.
Agents prepare drafts and stop. A `published` stage is set only after the founder did it
or explicitly told the lead to do that specific post.
