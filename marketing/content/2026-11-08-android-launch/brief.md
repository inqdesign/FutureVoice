# Brief: nawana, now on Android (2026-11-08-android-launch)

- stage: brief → copy
- piece: ONE celebratory image, 1080×1350 (4:5, a single card, not a carousel), plus one
  short Threads post. Korean primary, English version alongside.
- source of truth: CLAUDE.md "Android moves WITH iOS" (one version number, every iOS change
  carries an Android line), BRAND.md, status.md (Play production is live), the Play listing
  in `FutureVoice-android/android/fastlane/metadata/android/` (title "나와나: 유창해진 나와
  언어학습"), and `scripts/android-sync/ledger.py` (what Android still owes, read 2026-11-08).

## One message

**나와나가 이제 안드로이드(Google Play)에도 나왔어요. 내 목소리를 한 번 복제하고, 유창해진
나와 통화하며 언어를 배우는 그 앱 그대로.**

EN intent: nawana is on Google Play now. The same app as on iPhone: clone your voice once,
then learn a language by talking with your fluent self.

The news is "it's here, and it's the same app". Nothing else: no feature tour, no version,
no comparison with iPhone.

## Who it's for

- A Galaxy (or any Android) owner who saw a nawana post, a friend's screen or the website
  and found it was iPhone-only. Their moment: "안드로이드는 없어요?" now has an answer.
  Korea is a Galaxy-heavy market, so this is a real share of the people who already scrolled
  past nawana once.
- Secondary: an iPhone learner whose partner, friend or second phone is Android, who can now
  pass the app on.
- Honest floor as always: someone who can already build a sentence, stumbling. Nothing here
  promises zero to fluent.

## Why now

Release news. Play production is live today (status.md). The day it ships is the day to say
it, once, warmly. It's a celebration, so the tone is glad and short, never hype.

## Proof in the app (what is true, what to stay away from)

True and safe to say:
- It's on Google Play, under the same name (나와나 / nawana).
- Same app, same core: clone your voice once, talk with your fluent self in your own voice,
  every talk becomes your own study material. Android carries the iOS version number
  (CLAUDE.md "One version number"), and every iOS change is ported or marked by hand.
- The first 20 minutes are free. That allowance belongs to the account on the server,
  not to the store, so it holds on Android too (see Risks: confirm before the outro line).

Do NOT say or show (iOS-only, or Android still owes it per the ledger):
- Any version number (the founder's instruction; production 1.3.0 and testing 1.3.1 differ
  today anyway).
- Siri / App Shortcuts, home-screen widgets, the Mac app, iCloud (Android syncs through
  Google Drive; best to name no sync at all here).
- The daily call "ringing through silent mode" (that's the AlarmKit wording, iOS only).
- Pronunciation scoring per sound, the pronunciation call, Speech seasons: Android still
  owes all three (ledger, 2026-11-08). So "same app" stays a general line. Never back it
  with a feature list that includes these.
- "Your iPhone account carries over / continue on Android": not verified (sign-in on
  Android is Google, and cross-platform sign-in wasn't checked). Leave it out.
- Prices: Play prices are set in Play Console and weren't checked for this piece. No
  prices on the image or in the post.

## The image: two directions, one picked

**A. Phone frame with the real Talk home.** A phone in the middle showing the Talk home with
the fluent-self ring, a pixel headline above.
- Problem: the kit's only device is `nw-phone`, an iPhone 17 Pro with a Dynamic Island, and
  every kit screen is measured from iOS captures (iOS status bar, glass buttons). An iPhone
  in an Android announcement contradicts the message. An "Android frame" around an iOS
  screen shows a screen the Android app doesn't have, which breaks "the app is shown as it
  is" (BRAND.md). Doing it honestly means a real emulator capture of the Android Talk home
  (the Android repo has a `.capture` build flavor) plus a new device frame, and a new device
  is the founder's design call. Too much for one celebration card, and the risk is mostly
  in the one thing that matters here: the phone.

**B. A big pixel headline with the Futureself, lit (PICKED).** No device. The card is the
announcement itself:
- Ground: the light card ground #F7F8FA with the faint 54px grid, ink #0D1117, the one
  accent #0A5CF5 (BRAND.md Visual).
- Centre: a large `nw-futureself` **pill** (`shape="pill"`, default blue theme, light
  palette, `mode="speaking"`, `level="voice"`), clipped in its capsule as always. It's the
  app's face, it's in the kit, and it shows nothing that could be wrong on Android. The
  celebration is the mosaic itself: the kit draws its centre-out ignition, so the still is
  taken at full light (and an optional MP4 lets it light up and speak).
- Above it: the headline in the pixel display face (Galmuri14 for Hangul, Geist Pixel for
  Latin). Very large, two lines at most. Intent: "now on Android". Under it, one body-sans
  line that carries the message (same app, your own voice, your fluent self). The
  copywriter writes both natively in each language; no source sentences here.
- Bottom (the outro's job on a single card): nawana wordmark · "Google Play" as the
  where-to-get-it line · nawana.app · the free-20-minutes line if confirmed. For the Play
  mark, use EITHER the official unmodified "Get it on Google Play" / "Google Play에서
  다운로드" badge (Google's badge guidelines: no recolouring, minimum size, no other
  device art) OR plain text "Google Play" in the pixel face. Designer's pick; plain text
  sits better on brand and avoids the badge rules. **No Android robot** (off brand, and
  its licence wants attribution).
- Optional sticker, only if the card feels empty: one real line from the kit
  (`nw-bubble who="self"`, a short informal English line from the fluent self, kit sample
  text) near the pill, as if the fluent self is saying hi. One sticker at most. Its words
  are MATERIAL (English), casual, warm through interest, never longing ("I missed you"
  is out).
- Not allowed: confetti, emoji, hype words, a fake Android screen, the Futureself as a
  background texture.
- Deliverables: `renders/01.png` (the post image) and, optionally, `renders/01.mp4`
  (8–10 s loop: the pill lights centre-out, then speaks). Threads takes either; the PNG is
  primary. Make a ko card and an en card (`renders/01-ko.png`, `renders/01-en.png`).
- Build it as a one-card page in the piece folder (e.g. `card.html?lang=ko|en`) from the
  carousel template's ground and type rules, recorded with `record.mjs` at 1080×1350.
  It's a variant of the outro/cover pattern, not a new layout, but it's still a design
  choice, so the founder sees it before it goes anywhere.

## Threads post (intent for the copywriter)

- Korean primary (해요체, no "당신"), English version written fresh, not translated.
- Short: 2–4 lines, well under 500 chars. Line 1 is the news (now on Android / Google
  Play). Line 2 says what the app is in a single breath (your own cloned voice, your fluent
  self, the same app as on iPhone). Then where to get it. A warm thanks to people who
  waited is fine, kept to a clause, and only as a general thank-you: no names, no tester
  counts, no invented "you asked for it" quotes.
- Positive first; no limits or "still missing" in the post.
- One topic tag at most (Threads), e.g. 영어회화 or 안드로이드; no hashtag pile.
- Link: see open question 1.

## Channels

- Threads: the one image + the post (the founder's request).
- Optional, the founder's call: the same PNG as a single Instagram post, and a community
  news item. Release news on the community page is normally posted by `beta.sh` for iOS;
  check whether an Android launch item already exists before drafting one, so it isn't
  posted twice.
- Not a feature-series entry (this is news, not "나와나로 할 수 있는 것").

## Risks / copy traps

1. **"같은 앱" claims.** OK as a general line. Wrong the moment it's backed by a list that
   includes pronunciation scoring, the pronunciation call, Speech seasons, Siri, widgets,
   iCloud or the Mac. Reviewer: FIX any feature named that isn't in the "true and safe"
   list above.
2. **No version number** anywhere (image, post, alt text).
3. **Free 20 minutes on Android:** server-side and per account, so it should hold, but the
   reviewer confirms Android signup gets the same free pool (`AccountStatus.freeGrantSeconds`
   / the signup grant) before the outro line goes on the card. If unsure, drop the line.
4. **Google Play branding:** use the badge unmodified or not at all; no robot; "Google Play"
   is Google's trademark, so write it as is (not "구글플레이스토어" variants).
5. **Availability by country:** not checked which Play storefronts list the app. Don't say
   "everywhere" or name countries.
6. **No account carry-over claim**, no prices (both unverified for Android).
7. **The Futureself stays clipped** in the pill, light palette. No dark card.
8. Korean is written, not translated (BRAND.md). No em dashes in the post (founder rule
   for anything sent or posted).

## Success signal

- Threads views, likes, reposts and replies on this post (admin console 마케팅 tab), and
  replies asking about the Android app (how many, what they ask).
- Play Console: store listing visitors and installs in the 7 days after the post (the
  founder reads it; the team doesn't sign in).
- PostHog, read-only, a week later: new Android installs/signups (by `$os`) against the
  week before. Aggregate only; no user data in any report.

## Open questions for the lead / founder

1. **Which link goes in the post:** the Play listing
   (`https://play.google.com/store/apps/details?id=com.roro.futurevoice`, package from
   `build.gradle.kts`, not opened/verified) or nawana.app? The website has no Google Play
   badge or link yet (grep of `web/index.html` / `launch.html`), so nawana.app alone would
   send Android people to a page that only offers the App Store. Recommend the Play link in
   the post, nawana.app on the card.
2. Badge or plain "Google Play" text on the card (designer proposes, founder picks).
3. Post the same image on Instagram too, or Threads only as asked?
