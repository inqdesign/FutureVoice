# Program team — creators and challengers

The team that gets cohort 1 ready and runs it. Lead = the main session under `/program`.

| Agent | Owns | Never |
|---|---|---|
| `prog-web` | `web/creators.html`, the check-in page, the challenge tab in `web/ko.html` | deploys |
| `prog-server` | `supabase/migrations`, `supabase/functions/{creator-apply,stripe-*}`, `admin/src/creators.*`, Stripe objects | applies a migration, deploys, sets a secret |
| `prog-app` | the iOS and Android apps (what the program needs from them) | uploads a build |
| `prog-writer` | every word a participant reads: page copy, mails, DMs | sends anything |
| `prog-desk` | the state of the cohort, read from production: who applied, paid, kept the days | writes to production, contacts anyone |
| `prog-reviewer` | the gate: rules, code and live state agree | fixes what it finds |

- `RULES.md` is the one source for what was decided. `PLAN.md` is the ordered list and its status.
- Sub-agents cannot call each other: every hand-off goes through the lead and these files.
- Production writes (migrations, deploys, secrets, Stripe changes that cost or charge) are
  the founder's: the team hands over the exact commands, in order.
- Other sessions edit the same tree. Touch only your own hunks; never revert or reformat a file.
