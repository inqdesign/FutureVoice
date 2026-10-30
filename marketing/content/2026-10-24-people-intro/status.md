# status — people-intro

- **stage:** brief
- **version/build:** 1.2.3 (119), phase upload (autopilot)
- **request (autopilot):** Tell what's new in 1.2.3 — Find people, a person's page and the map card now show the **intro that person published** (fix cc938a0). You can see who you're about to talk to before you call. (Published intros only; private notes never leave the phone.)
- **owner:** lead (autopilot)
- **NARROWED SCOPE (lead decision):** Only ONE 1.2.3 surface is captured — the **Find-people list** (`marketing/captures/people.png`), which shows each stranger's published intro (occupation/portrait line + interests/location). The person's full PAGE and the Watch MAP card have no capture (watchtab.png is the stale old Watch tab), so the whole carousel is built on the Find-people list screen alone (scroll + focus motion). Honest and sufficient for the message "see who you're about to talk to."
- **kit:** needs a NEW Find-people list state — `people.js` only renders the Watch tab + a person's card. `mkt-web` builds it from `people.png` per FIDELITY.md.
- **open questions:** —
