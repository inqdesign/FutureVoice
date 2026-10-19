# nawana brand rules

Every agent reads this before writing a word or drawing a pixel. These are the founder's
decisions; they are not to be re-argued in a draft. When something here and a request
disagree, ask the lead.

## What nawana is (one paragraph, keep it true)

An iOS app (Android in step) where you clone your own voice once and then practise a
language by talking with your **fluent self** — someone who sounds exactly like you, a few
years on, already fluent. Talk (calls on any topic, the news, your own situations), Watch
(see a situation played before you live it), Review (every talk becomes a book: words,
expressions, corrections, shadowing, spaced review answered out loud), Speech (read a
script on a prompter, get scored, challenge boards), a daily call that rings like an
alarm, a routine, a weekly report and a weekly test built only from your own week.
Details and limits: `CLAUDE.md`. If a feature isn't there, it doesn't exist.

## Voice

- **Write each language natively. Never translate.** Korean copy is written as Korean
  from the intent, not from an English draft (and the reverse). Briefs to a copywriter
  carry intent, never source sentences to convert.
- **Korean registers:**
  - carousels, captions, community, app-like copy: 해요체 (“…말해요”, “…돼요”).
  - website headlines: short declarative 평서문 (“전화를 받는다.”) — the site's own style.
  - founder emails/announcements: 합니다체.
  - never “당신”. Address the reader without a pronoun.
- **The fluent self speaks informally** in every language (반말 / casual English). It never
  longs or misses (“보고 싶었어”, “I missed your voice” — no). Warmth = interest in you.
- **Positive first.** A title or first line says what you do or get. A loss, a limit or a
  reason comes second, if at all.
- **One line, no rationale.** Say the conclusion. Don't argue for it in UI-like copy.
- **Never grade the reader.** No “for beginners / for experts”. Plans describe what they let
  you do, not who you are.
- **Honest floor:** nawana is not for absolute beginners — the floor is “building a
  sentence, stumbling”. Never promise zero-to-fluent.
- **The comparison is an AI tutor vs me** (founder, 2026-10-13): an AI tutor speaks in
  someone else's voice; the fluent self speaks in mine, so the line sounds like "I could say
  that too". Imitating someone else's voice feels like acting. Don't belittle AI tutors or
  native speakers.
- Conversation lines, scripts, words = the learning MATERIAL → in the target language
  (English by default). Labels and explanations around them → the reader's language.
- No emoji as decoration in visuals. No hype words (혁신, 최고의, revolutionary).

## Visual

- **Light theme.** Card ground #F7F8FA with the faint 54px grid; ink #0D1117; the one accent
  is the app's blue **#0A5CF5**. Other colours only where the app uses them (green check,
  orange score, red record).
- **Type:** display = pixel (Geist Pixel, Galmuri14 for Hangul) for titles and numbers;
  body = system sans. Don't mix in other faces.
- **The app is shown as it is.** Phone screens come from `web/kit` (real app, measured from
  simulator captures). Never draw an app screen, invent a button, or show a feature state
  the app doesn't have. A new screen = capture + fidelity pass (`marketing/FIDELITY.md`).
- **The device** is the kit's `nw-phone` (iPhone 17 Pro proportions, island, status bar).
- **Futureself mosaic** appears only clipped inside a shape (the pill, a circle), light
  palette, never as a background texture.
- **Carousel layout** (4:5, 1080×1350): fixed text block on top (series eyebrow + n/total,
  pixel title, 2-line description), the live screen below; cover card first; outro last
  (wordmark · “유창한 나에게 언어를 배우세요.” · “첫 20분은 무료예요” · nawana.app).
  Keep the text layout; vary the screen and the motion.
- **Stickers** (small real UI pieces around a phone) are allowed: correction card, a line,
  the pill, a word card, a score — all from the kit.
- Design choices (palette, a new layout, a new motif) are the founder's: show it, don't
  just ship it.

## Facts that must stay true (check before every piece)

- **Prices** come from App Store Connect (live) and `subscription_plans`, never from docs:
  Light 150 min + 10 scenes / mo — $9.99 · ₩15,000 · €9.99 (annual $99.99 · ₩149,000)
  Plus 600 min + 30 scenes / mo — $24.99 · ₩29,000 · €22.99 (annual $249.99 · ₩290,000)
  Max 1,200 min + 30 scenes / mo — $49.99 · ₩58,000 · €44.99 (monthly only)
  First 20 minutes free, no trial. Annuals are “2 months free”.
  Re-check: `scripts/asc-annual-prices.py` (`effective_monthly`) and the DB.
- Removed / not true: Plus is NOT unlimited; there is NO free trial; the weekly test has no
  streak flame or gauge; a missed daily call leaves no "I'll call again" banner.
- Numbers on a slide (scores, minutes, counts) are illustrative sample data from the kit —
  never present them as user statistics or results.
- Growth is the priority now: never suggest cutting free minutes or limits.

## Never

- Post, publish, deploy, email or spend without the founder's explicit OK for that item —
  except the autopilot scheduler posting a reviewer-PASSed piece after the veto window.
- Use Supabase Storage for media (web static files only: `web/community/…`).
- Touch files another session is editing; discard uncommitted work; reformat a whole file.
- Impersonate people, invent testimonials, or show a real user's data or name
  (the founder's own name included) in public material.
