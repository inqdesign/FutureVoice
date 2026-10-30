# copy — people-intro (1.2.3 / build 119)

IG carousel (6 cards: 01 PNG · 02–05 MP4/PNG · 06 PNG) · Threads (first 5) · community series (cat `watch`)
Series: 나와나로 할 수 있는 것
Written 2026-10-24 from `brief.md` + `status.md` (NARROWED SCOPE). Korean written as Korean, English as
English; they agree in meaning, not wording. 해요체 throughout, no 당신, no em dash anywhere in this file.

The one message: 통화를 걸기 전에, 상대가 누구인지 본인이 직접 쓴 소개로, 그것도 내가 배우는 언어로 먼저 읽어봐요.
Less friction (I know who this is) + free reading practice (the intro is MATERIAL, so target language).

## For the designer — the scope is ONE screen

- **Every card's app screen is the Find-people list** (`FindPeopleSheet`, the "낯선 사람 / Strangers"
  section of `marketing/captures/people.png`): each row = a face/initial + an intro line (occupation
  or portrait) + interests/location. The person's full PAGE and the Watch MAP card have NO capture and
  are NOT available — do NOT draw them. Vary cards with scroll + focus motion on the one list, not with
  a new screen. (Kit gap: `people.js` renders only the Watch tab + a person's card; `mkt-web` builds the
  Find-people list state from `people.png` per FIDELITY.md.)
- **No real user data.** Every face, name and intro on a slide (holly, Dong, Mark, Sunny, Emma…) is
  kit/sample data. Never present a sample intro as a real person's published profile.
- **Don't imply a clone.** A stranger's voice is a preset. The real list header already says this in app
  ("그 사람의 소개를 AI가 기본 목소리로 말하는 것이고, 본인 목소리는 쓰이지 않아요") — lean on it, don't contradict it.
- The privacy mark on card 04 stays quiet (top text block or a small sticker), never drawn onto the app
  screen as a wall.

---

## 01 — Cover (still PNG, reads in the grid)
eyebrow: 나와나로 할 수 있는 것 · 01 / 06
title (ko): 통화 걸기 전에\n누군지 봐요
desc (ko): 목록 속 낯선 사람들, 저마다\n**자기 소개**를 써 뒀어요.
title (en): See who\nyou'll call
desc (en): Strangers in the pool, each with\ntheir own **intro** written out.
screen: Find-people list (Strangers section), rows with faces + intro lines — must read as a still in the grid
sticker: one person row (face + one intro line) pulled out beside the phone
footer (ko): 옆으로 넘겨보세요 → · nawana.app
footer (en): Swipe → · nawana.app

## 02 — People, not names (list, slow scroll down the Strangers section)
eyebrow: 나와나로 할 수 있는 것 · 02 / 06
title (ko): 이름이 아니라\n사람이에요
desc (ko): 낯선 사람, 가상 인물, 다른 학습자.\n저마다 **소개 한 줄**이 달려요.
title (en): People,\nnot names
desc (en): Strangers, characters, other learners,\neach with a **line of their own.**
screen: the Strangers list on a slow scroll — enough rows to read as "a lot of people, each with a line"
sticker / reaction: a single row (face + one intro line) lifted out beside the phone

## 03 — In their own words (list, focus/zoom on one row's intro line)
eyebrow: 나와나로 할 수 있는 것 · 03 / 06
title (ko): 본인 말로\n써 뒀어요
desc (ko): 뭐 하는 사람인지, 뭘 좋아하는지\n**자기가 직접** 쓴 소개예요.
title (en): In their\nown words
desc (en): What they do, what they're into,\nwritten **by them.**
screen: the list with one row in focus — its occupation/portrait line and interests clearly readable
sticker / reaction: none

## 04 — Reading it is practice too (list, a target-language intro line held for a beat)
eyebrow: 나와나로 할 수 있는 것 · 04 / 06
title (ko): 읽는 것도\n공부가 돼요
desc (ko): 소개가 배우는 언어로 쓰여 있어요.\n**공개한 것만** 보여요.
title (en): Reading\ncounts too
desc (en): The intro's in the language you're learning.\nOnly **what they published** shows.
screen: the list, one row's target-language intro line held in focus for a beat (can be a still)
mark (quiet, top block or sticker — NOT on the app screen): 비밀은 폰 밖으로 안 나가요 / Nothing private leaves the phone

## 05 — Then start the call (list, one row focused/pressed, ready to tap Talk)
eyebrow: 나와나로 할 수 있는 것 · 05 / 06
title (ko): 알고 나서\n통화 시작
desc (ko): 누군지 알고 탭하면 돼요.\n목소리는 **기본 목소리예요.**
title (en): Then start\nthe call
desc (en): Tap once you know them.\nThe voice is a **preset.**
screen: the list with one row in a pressed/selected state, as if about to tap into the call (the call itself has no capture — stay on the list)
footnote (quiet, never a headline): 낯선 사람 목소리는 기본 목소리예요, 내 클론이 아니고요 / A stranger's voice is a preset, never your clone

## 06 — Outro (standard outro)
eyebrow: 나와나로 할 수 있는 것 · 06 / 06
wordmark: nawana
line (ko): 유창한 나에게 언어를 배우세요.
line (en): Learn a language from your fluent self.
free line: 첫 20분은 무료예요 · First 20 minutes free
url: nawana.app
screen: `nw-futureself` (speaking), no phone

---

## Instagram caption (ko)

낯선 사람한테 전화 걸기, 망설여지잖아요.
이제 걸기 전에 누군지 봐요.

Find people 목록엔 낯선 사람, 가상 인물, 다른 학습자가 있어요. 저마다 자기 소개를 한 줄씩 써 뒀어요.
뭐 하는 사람인지, 뭘 좋아하는지, 본인이 직접 쓴 말로요.
소개가 내가 배우는 언어로 쓰여 있어서, 읽는 것만으로도 공부가 돼요.
공개한 것만 보여요. 비밀스러운 건 폰 밖으로 안 나가요.
누군지 알고 탭하면, 통화가 시작돼요.
(낯선 사람 목소리는 기본 목소리예요. 내 클론이 아니고요.)

첫 20분은 무료예요 · 프로필 링크

#영어회화 #영어공부 #스피킹 #전화영어 #nawana

## Instagram caption (en)

Tapping Talk on a stranger always feels a bit odd. Now you see who they are first.

The People pool has strangers, characters and other learners. Each one wrote a line about themselves.
What they do, what they're into, in their own words.
The intro's in the language you're learning, so just reading it is practice.
Only what they chose to publish shows up. Nothing private ever leaves their phone.
Once you know who they are, tap and the call starts.
(A stranger's voice is a preset, never your own clone.)

Your first 20 minutes are free · link in bio

#languagelearning #learnenglish #speakingpractice #영어회화 #nawana

---

## Threads text — ko (≤ 500 chars, conversational, not the caption pasted)

모르는 사람한테 전화 걸려고 하면 "무슨 얘길 하지" 싶어서 멈칫하잖아요.
나와나 Find people에선 걸기 전에 그 사람 소개를 먼저 봐요. 낯선 사람이든 다른 학습자든, 뭐 하는 사람인지 뭘 좋아하는지 본인 말로 써 뒀어요. 그것도 내가 배우는 언어로요, 그래서 읽는 것도 공부가 돼요.
공개한 것만 보이고, 비밀은 폰 밖으로 안 나가요. 목소리는 기본 목소리고요.

## Threads text — en (≤ 500 chars, conversational, not the caption pasted)

Tapping call on someone you don't know is exactly where "but what do I even say" kicks in.
In nawana's People, you read who they are before you dial. Strangers, other learners, whoever: what they do, what they like, in their own words, in the language you're learning. So reading it already counts as practice.
Only what they published shows, nothing private leaves their phone, and the voice is a preset.

---

## Community series entry (new; the 낯선 사람 소개 편)

id: TODO (publisher — e19 is the last live id; e20 accent-words, e21 coach-suggestion, e22 add-your-own
are in progress, so likely e23 — confirm with the lead before writing the entry)
cat: watch
slides: 6 (01–06, 720×900), ko/en title+tagline above; mirrors the IG carousel the same day.
ko: { title: "누군지 보고 걸기", tagline: "통화 걸기 전에 상대가 누군지 본인 소개로 봐요" }
en: { title: "Meet before you call", tagline: "See who you're about to talk to, in their own words" }

Slots behind e09 사람과 연습 as the door INTO the People pool. Founder approval before deploy.

---

## Open questions (for the lead)

1. **Fidelity (blocking for design).** The Find-people list is a NEW kit state — `people.js` renders only
   the Watch tab + a person's own card. `mkt-web` must build the Strangers-list state from `people.png`
   before the designer can render any card. Whole carousel rides on this one screen.
2. **Community id.** Left TODO; e20/e21/e22 are claimed by in-progress pieces, so e23 is the likely next
   free id — publisher confirms.
3. **IG handle.** CHANNELS.md still says "ask the founder"; copy uses "프로필 링크" / "link in bio" so no
   handle is needed, but confirm the bio link is live.
4. **Sample data on slides.** holly / Dong / Mark / Sunny / Emma and their intro lines are kit sample
   data (from `people.png`) — confirm it's fine to ship as the visible example and reads naturally.
