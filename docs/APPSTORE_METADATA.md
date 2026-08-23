# App Store Connect — Submission Metadata

> Source of truth for the App Store listing. Copy fields directly into App Store Connect.
> App: **nawana** · Bundle: `com.roro.futurevoice` · Seller: Dear RoRo (Munich) · iOS 17+
> Character limits are Apple's hard caps; counts shown are within limit.

---

## Core listing fields

| Field | Value |
|---|---|
| **App Name** (≤30) | `nawana: Speak Fluently` (22) |
| **Subtitle** (≤30) | `Talk with your fluent self` (26) |
| **Bundle ID** | `com.roro.futurevoice` |
| **Primary Category** | Education |
| **Secondary Category** | Productivity |
| **Price** | Free (with In-App Purchases / subscriptions) |
| **Age Rating** | **4+** (see §4 — every questionnaire answer is No; the in-app 16+ gate is a separate thing, see §4a) |

### Support / URLs
| Field | Value |
|---|---|
| **Marketing URL** | https://nawana.app/ |
| **Support URL** | https://nawana.app/ (add a /support or contact page) |
| **Privacy Policy URL** | https://nawana.app/privacy.html (live; ko at /privacy-ko.html) |
| **Copyright** | © 2026 Dear RoRo |

---

## Promotional Text (≤170)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/en-US/promotional_text.txt` (153자)


## Description (≤4000)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/en-US/description.txt` (2,621자)


## Keywords (≤100, comma-separated, no spaces)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/en-US/keywords.txt` (96자)


## What's New (release notes, ≤4000)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/en-US/release_notes.txt`


## App Review notes (private — not shown to users)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/review_information/notes.txt` — 2026-08-19: 익명 시작 온보딩(클론 후 Apple 로그인) 반영


### Permission usage strings (verify in Info.plist)
- **Microphone** — "nawana needs the microphone to hear you speak during a conversation."
- **Speech Recognition** — "nawana uses speech recognition to understand what you say."

---

## In-App Purchases (fill display names / descriptions in ASC)

Two tiers, four products. **The buyer only ever reads the localized Display
Name**, so that is where the real tier name goes — the product ids are permanent
and say something else (see the warning below).

| Product id (permanent) | Display name EN | 표시 이름 KO | Pool per billing period |
|---|---|---|---|
| `…daily_monthly` / `…daily_annual` | Light | 라이트 | 150 min talk · 60 Watch scenes |
| `…unlimited_monthly` / `…unlimited_annual` | Plus | 플러스 | **Talk: no limit** · 120 Watch scenes |

Descriptions (match the paywall's own lines — one situation, then the size):
- **Light** — Keep it up as a habit. 150 minutes of talk and 60 Watch scenes each billing period.
- **Plus** — Talk as much as you want, whenever you want. No limit on talk time; 120 Watch scenes each billing period.

> **Never write "Unlimited" in the display NAME.** The ids read `unlimited_*`
> only because they were registered before the rename and an Apple product id
> can never be renamed or reused — not even after removal from sale
> (`20260820220000_keep_registered_apple_ids`). The tier is called **Plus**.
>
> Plus's talk time genuinely has no cap since `20260821120000`, so the
> description may say so — but it must ALSO name the Watch count, which is a
> real limit. A description that says "unlimited" full stop, with a 120-scene
> cap unmentioned, is the misleading-subscription rejection.
>
> **The count was 600 until 2026-08-23** (`20260823140000_plus_scene_count`) —
> 20 a day, unspendable, and $114/mo of upstream cost against $17 net. If any
> of this was already entered in App Store Connect, edit it there too: the
> app's paywall reads `monthly_scenes` live and already shows 120, so a stale
> store description promises more than the app delivers.
> `fastlane/metadata/review_information/notes.txt` explains the mismatch to the
> reviewer — keep that paragraph.

> These were "Standard" and "Heavy / Pro" until 2026-08-20. A name must not tell
> the buyer what they are: "heavy user" tells someone they are the small one.
> Tier names say SIZE. See `AccountStatus.tierName`, the one place they live.

> Confirm exact product IDs, prices, and durations in `PaywallView.swift` /
> `subscription_plans` / App Store Connect before submission.

---

# 한국어 (ko) 로컬라이제이션

| 필드 | 값 |
|---|---|
| **앱 이름** (≤30) | `nawana: 유창해진 나와 대화` (18) |
| **부제** (≤30) | `영어회화, 원어민 말고 내 목소리로` (19) |

> 구조: 이름 = 브랜드 + 이 앱만의 훅("유창해진 나"), 부제 = 최상위 검색어(영어회화) + 시장 반전("원어민처럼" 문법을 뒤집는 "원어민 말고") + 차별점(내 목소리). 이름과 겹치는 단어 없음.
> 대안: `원어민 흉내는 오늘로 끝` (도발형, 키워드 없음) · `영어 스피킹, 목표는 원어민이 아니라 나`

### 프로모션 텍스트 (≤170)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/ko/promotional_text.txt` (96자)


### 설명 (≤4000)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/ko/description.txt` (1,271자) — 영어 번역이 아니라 새로 쓴 한국어 (해요체)


### 키워드 (≤100)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/ko/keywords.txt` (58자) — 전화영어·원어민·보이스클론 추가


### 새로운 기능 (릴리스 노트)

> **소스는 fastlane** — 2026-08-19 코어 메시지 개편으로 전면 재작성. 아래 파일을 그대로 ASC에 붙여넣는다 (문서에 카피를 중복 보관하지 않는다):
> `fastlane/metadata/ko/release_notes.txt`


## Submission checklist — in dependency order

### 0. Blockers found in code — ALL FIXED 2026-07-23
- [x] **Account deletion in-app** — MeTab "Delete account" → `account-delete` Edge Function (deletes ElevenLabs clones, cancels Stripe web sub, destroys auth user; all tables cascade) + `AppState.wipeLocalData()`. DEPLOYED 2026-07-28 (verified 401 without auth).
- [x] **Privacy Policy page** — https://nawana.app/privacy.html + /privacy-ko.html LIVE (200) as of 2026-07-28.
- [x] Info.plist mic + speech strings rebranded to nawana
- [x] `CFBundleShortVersionString` → 1.0.0 (app + widget)
- [x] Export compliance — `ITSAppUsesNonExemptEncryption=false` already set
- [x] No analytics SDK → no ATT prompt, no Tracking declaration

### 1. Agreements, Tax, and Banking (START FIRST — approval takes days)
- [ ] Sign Paid Applications agreement + banking/tax info (required to sell subscriptions)

### 2. Subscriptions (Monetization)
- [ ] One Subscription Group, two tiers — display names **Light** and **Plus** (see the IAP table above; the product ids say something else and cannot be changed)
- [ ] Product IDs must EXACTLY match the server plan catalog's `apple_product_id` (StoreKitService loads IDs from the server)
- [ ] Localized display name + description per product (EN + KR)
- [ ] Prices + free-trial Introductory Offer (paywall has trial logic)
- [ ] Subscription review screenshot (paywall capture)
- [ ] Attach subscriptions to the first version's review submission

### 3. App Privacy labels
- [ ] Audio data (voice clone — linked to user, app functionality)
- [ ] **Sensitive Info** — the voice model is biometric data (GDPR Art. 9 / BIPA voiceprint / PIPA sensitive). Declare it; "Audio Data" alone under-declares what a *cloneable* voice is.
- [ ] Email/name (Sign in with Apple) · Purchase history · User content (conversations)
- [ ] Tracking: none

### 4. Age rating questionnaire → **4+ (current rating is correct — leave it)**

Verified against the live questionnaire and the rendering code on 2026-08-18.
**Every question answers No.** The rating in ASC today (4+ / AL Brazil / ALL
Korea / 00+ Vietnam) is the honest result; do not raise it.

| Question | Answer | Why |
|---|---|---|
| Violence · Sexual content · Nudity · Profanity · Horror · Alcohol/tobacco/drugs · Simulated gambling · Contests · Gambling | **No** | Language-practice dialogue; none of these are themes the app trades in. |
| **Parental Controls** | **No** | No guardian-facing monitoring or restriction features exist. |
| **Age Assurance** | **No** | The 16+ step is a *self-declaration* (`ConsentStore`), not a confirmation. Apple's bar in this section is explicit in the next question — "at a minimum, the **Declared Age Range API** is called" — and the app never calls it (it is iOS 26+; the deployment target is 17). Yes here would claim a mitigation we cannot back, and No costs nothing: see §4a, the gate is contractual, not a rating input. |
| **Unrestricted Web Access** | **No** | No `WKWebView` / `SFSafariViewController` anywhere. Every outbound link (App Store subscriptions, privacy policy) hands off to Safari via `Link` / `openURL`. Yes here forces 18+. |
| **User-Generated Content** | **No** | See "Why Find people is not UGC" below — the one answer worth understanding before anyone re-derives it. |
| **Social Media** | **No** | The definition needs redistribution, *amplification*, or interaction that "visibly spreads content to many users". There is no feed, no ranking, no likes, no follows, no comments, no resharing; bookmarks are local `UserDefaults`, and nothing a learner does reaches a persona's author — no notification, no shared record. |
| Social Media Disabled for Users Under 13 | **n/a** | Only asked when Social Media is Yes. |
| **Messaging and Chat** | **No** | No user-to-user path exists. `PublicPersonaService` touches exactly one table, `public_personas` — there is no message or DM table in the schema. Talk is learner↔AI; Find people is an AI portrayal. |
| **Advertising** | **No** | No ad SDK, no IDFA, no ATT prompt. Analytics is hand-written PostHog events only. |

#### Why Find people is **not** UGC (read this before changing the answer)

The data model reads like UGC and the UI is not, which is exactly the trap.
`public_personas` does store a user-written `intro` — but
[`FindPeopleSheet`](../FutureVoice/Views/FindPeopleSheet.swift) renders that
paragraph **only for curated characters** (`group == .character` /
`personaKind != "user"`). A real learner's row and card fall to the `else`
branch and show four identity facets and nothing more: **display name,
occupation, location, interests.** The intro prose — which carries things like
household composition — reaches the *model* and never another human.

So the content another learner actually consumes is AI-generated conversation,
not text a user wrote. The four facets are parameters for choosing a practice
partner, not published content. Reading the data model alone (or CLAUDE.md's
description of it) produces the wrong answer here; read the rendering code.

If that guard is ever removed — if a real learner's `intro` becomes visible on
a browsable card — this answer flips to **Yes**, and Guideline 1.2 (report,
block, takedown, publish-time filtering) applies in full.

#### 4a. The in-app 16+ gate is NOT the age rating

Two different things, and conflating them produces bad decisions in both
directions:

- **The App Store rating** measures *content suitability*. Ours is 4+.
- **`ConsentStore.minimumAge = 16`** measures *legal eligibility*. It exists
  because ElevenLabs — the sub-processor that builds the voice model — bans
  under-13s outright, requires parental consent for 13–17, and forbids passing
  its Services on under terms more permissive than we received them. There is
  no way to verify a real parent in-app, so the floor clears the 13–17 band
  entirely. GDPR Art. 8 (16 in Germany, where the seller is registered) lands
  on the same number for the voice consent, which is Art. 9 special-category
  data and therefore consent-based.

A 4+ rating alongside a 16+ eligibility gate is normal and not a contradiction
— compare any banking app. Do **not** raise the rating to "match" the gate, and
do **not** drop the gate to match the rating: removing it means either building
verifiable parental consent or breaching the provider terms.

⚠️ The ElevenLabs clause above lives only in `ConsentStore`'s doc comment; no
copy of the terms is in `docs/contracts`. The whole number rests on it — verify
against the current ToS before submitting.

#### Open, unrelated to the rating

- **The four published facets are auto-published, not opted into.**
  `PublicPersonaService.autoSyncMyPersona` runs at app start and on tab entry,
  gated only on a 30-character intro. Disclosed in the privacy policy as of
  2026-08-18; whether it should be opt-in is a product decision.
- **Those four fields are free text with no report path.** A much smaller
  surface than 1.2 UGC, but a publish-time check on short fields is cheap
  insurance.

### 5. Pricing: Free + country availability

### 6. Version metadata (copy from this doc, EN + KR)
- [ ] Promotional text · Description · Keywords · What's New · URLs · Copyright

### 7. Screenshots
- [ ] 6.9" (iPhone 16 Pro Max) set, up to 10 — suggested order: Talk call → Watch scene → Shadow verdicts → word cloud → Progress (reuse DEBUG capture harness)
- [ ] No iPad screenshots needed if iPhone-only

### 8. Build
- [ ] Archive 1.0.0 → upload → wait for TestFlight processing → select build on version page

### 9. App Review information
- [ ] Contact info
- [ ] Review notes: voice clone is the USER'S OWN voice, created via explicit 60-second onboarding recording (deepfake-guideline defense); explain onboarding flow
- [ ] Demo video link if possible (so the reviewer isn't blocked by voice-clone onboarding)

### 10. Submit
```
