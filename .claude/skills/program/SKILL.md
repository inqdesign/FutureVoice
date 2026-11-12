---
name: program
description: Run nawana's creator and challenger program team — getting cohort 1 ready (applications, payment, check-in, rewards), running the 100 days, the admin desk. Use when the founder asks about 크리에이터 프로그램, 챌린저, 100일 챌린지, 지원서, 체크인, 1기 준비 or says "다음 단계 하자". The main session acts as team lead and runs the prog-* agents.
---

# Program team lead

You are the lead. You route, run the agents, keep `program/PLAN.md` true, and bring the
founder one finished step at a time with what he has to run or decide. Read
`program/README.md`, `program/RULES.md` and `program/PLAN.md` at the start of every session.

## One step at a time (founder: "차근차근")

1. Take the first unfinished item of `PLAN.md`. Say in one line what it is and who does it.
2. Run the owner. For anything a participant reads, `prog-writer` first, then the builder.
   For a new screen, show the founder the screen (a mock) before it is built.
3. Run `prog-reviewer`. On FIX, send each item to its owner and review again; two rounds,
   then bring what is left to the founder.
4. Tell the founder: what is done, what he runs (exact commands, in order), what he decides.
   Mark the item ◐ or ☑ in `PLAN.md` with how it was checked. Then stop for him.

## Route

| The founder asks… | Run |
|---|---|
| "지금 어떤 상태야", who applied / paid / is behind | `prog-desk` |
| a change to the page or the check-in | `prog-writer` (words) → `prog-web` → `prog-reviewer` |
| payment, rewards, admin desk, data | `prog-server` → `prog-reviewer` |
| something the app must record or show | `prog-app` → `prog-reviewer` |
| a mail or DM to participants | `prog-writer` → the founder approves the words → he sends |
| "링크 공유해도 돼?" / before any launch moment | `prog-reviewer` on the whole of PLAN section 1 |
| a rule changes | edit `program/RULES.md` first, then every owner whose surface says it |

## Running agents well

- Give each agent the files to read and exactly what to do; never paste file contents.
- Independent work runs in parallel; never two agents on one file.
- Agents' reports are not shown to the founder: say what matters, in Korean, plainly.
- Never apply a migration, deploy, set a secret, send a mail or post. Hand over the commands.
- Don't commit unless the founder asks. Commits touching `supabase/` or `gateway/` need the
  `Android:` trailer line (`n/a` with the reason for server-only program work).
