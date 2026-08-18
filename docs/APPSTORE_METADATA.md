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

> Editable without a new build. Source of truth is fastlane/metadata/<locale>/promotional_text.txt.

```
Record 60 seconds once. Then call your fluent self, shadow your own voice, and watch your words add up. Seven days free, cancel anytime.
```
(136 chars)

---

## Description (≤4000)

```
Speak a new language in the one voice you can actually become — your own.

nawana turns 60 seconds of your voice into your fluent self: your conversation partner, your shadowing target, and living proof that fluency is within reach. Your pitch, tone, and pace stay yours. The only thing that changes is the part you're training — the language.

TALK — practice by actually speaking
Call your fluent self and just talk. Free talk, a situation you choose, or news matched to your interests. Every turn, your sentence comes back the way your fluent self would say it — same meaning, more fluent. Sessions end in a scorecard graded across five skills, and every line you fumbled becomes a practice card automatically.

WATCH — live the moment before it happens
The scariest part of a foreign language is the blank — not knowing what to say next. Describe a real upcoming situation, or the people in your life, and watch your fluent self carry that exact conversation. Hear how you'd handle the negotiation, the small talk, the awkward ask — then master every word and line inside.

SHADOW — make the words yours
Understanding a phrase isn't owning it; your mouth needs the reps. Speak along with your fluent line, slow to 0.5×, loop the words that trip you — and get a per-word verdict on what you nailed, swapped, or skipped. The target is a voice you can actually match: yours.

REVIEW — until it sticks
Fumbled sentences return as speak-aloud drills right before you'd forget them — answered out loud, never multiple choice. A pool of ~8,000 CEFR-graded words sits underneath, and every word you use is ticked off automatically. Your level is estimated from the words you actually used — a measurement, not an opinion.

WHY YOUR OWN VOICE
A native speaker's voice was never yours — you can imitate it forever and never arrive. Your fluent clone keeps your timbre, so the only distance left between you and the goal is fluency itself. Your sentence, then the fluent version, in the identical voice — everything you hear in the difference is exactly what to fix.

YOUR VOICE, TREATED CAREFULLY
Sixty seconds at setup. The app never records you outside a conversation you started. Re-record or delete your voice anytime. Your sessions, drills, and progress live on your iPhone.

SUBSCRIPTION
A subscription buys talk time — five minutes a day, or an hour. Watch scenes have their own small daily count. Reviewing, replaying, and building situations never cost anything. Seven days free, cancel anytime.

Sixty seconds of setup. Your first conversation tonight.
```

---

## Keywords (≤100, comma-separated, no spaces)

```
language learning,voice clone,shadowing,pronunciation,English,ESL,AI tutor,conversation,practice
```
(96 chars)

> Notes: `speak`/`fluently`/`talk`/`fluent` are NOT here on purpose — the name and subtitle already index them, and repeating them wastes characters. Swap "English" for the launch market's target language if you localize. Avoid trademarked competitor names.

---

## What's New (release notes, ≤4000)

First public App Store release:
```
nawana is here.

Clone your voice once, then learn a language by talking with the fluent version of yourself — same timbre, same pace, just fluent.

• Talk — call your fluent self. Free talk, a situation you pick, or news matched to your interests. Every sentence comes back the way you'd have said it fluently.
• Watch — describe something coming up and watch yourself handle it before it happens. That's where the expressions come from.
• Practice — every line you fumbled returns as a speak-aloud drill, right before you'd forget it.
• Progress — your level, measured from the words you actually used. A measurement, not an opinion.

Seven days free. Thanks for being here at the start — the Send button in the app reaches me directly.
```

---

## App Review notes (private — not shown to users)

```
ABOUT THE VOICE CLONE (important for review):
- During onboarding the user records a 60-second sample of their OWN voice, with explicit consent, to create a personal text-to-speech voice (via ElevenLabs).
- The app can only clone the signed-in user's own voice — there is no way to import audio of another person or clone anyone else.
- The clone is used solely to speak the user's practice lines back in their own voice ("your fluent self"). Re-recording permanently deletes the previous clone; the user can delete their voice or entire account in-app (Me tab).
- Consent is a separate, recorded step shown before the microphone is ever requested (age 16+ and voice-model consent are two distinct toggles), because a voice model is biometric data under GDPR Art. 9, Illinois BIPA, and Korea's PIPA.

REVIEW LOGISTICS:
- Sign in with Apple is the only auth method; any Apple ID works.
- Onboarding requires microphone + speech recognition permissions and the 60-second recording before the main app unlocks.
- All AI requests (Gemini, ElevenLabs) route through our Supabase Edge Functions; no provider API keys ship in the binary.
- Subscriptions are auto-renewable and buy talk time per day (Daily 5 min, Unlimited 60 min), with a 7-day free trial. Restore and cancel via the App Store. There is no free tier: the voice clone and the first spoken greeting are free, and the first conversation reaches the paywall.
- Reviewing, replaying, and building situations never consume talk time, so the app remains usable after the daily allowance is spent.
- Any trouble reaching a paid feature during review: contact hello.dearroroapp@gmail.com and we will respond quickly.
```

### Permission usage strings (verify in Info.plist)
- **Microphone** — "nawana needs the microphone to hear you speak during a conversation."
- **Speech Recognition** — "nawana uses speech recognition to understand what you say."

---

## In-App Purchases (fill display names / descriptions in ASC)
Two subscription tiers (from the paywall):
- **Standard** — For a steady daily habit: conversations, shadowing, and review.
- **Heavy / Pro** — For heavy daily use: longer calls, more dialogues, more drills.

> Confirm exact product IDs, prices, and durations in `PaywallView.swift` / App Store Connect before submission.

---

# 한국어 (ko) 로컬라이제이션

| 필드 | 값 |
|---|---|
| **앱 이름** (≤30) | `nawana: 유창해진 나와 대화` (18) |
| **부제** (≤30) | `영어회화, 원어민 말고 내 목소리로` (19) |

> 구조: 이름 = 브랜드 + 이 앱만의 훅("유창해진 나"), 부제 = 최상위 검색어(영어회화) + 시장 반전("원어민처럼" 문법을 뒤집는 "원어민 말고") + 차별점(내 목소리). 이름과 겹치는 단어 없음.
> 대안: `원어민 흉내는 오늘로 끝` (도발형, 키워드 없음) · `영어 스피킹, 목표는 원어민이 아니라 나`

### 프로모션 텍스트 (≤170)
```
딱 60초만 녹음하세요. 유창해진 나와 통화하고, 내 목소리를 섀도잉하고, 쌓이는 단어를 확인하세요. iOS 베타 기간 무료.
```

### 설명 (≤4000)
```
정말로 될 수 있는 단 하나의 목소리 — 바로 내 목소리로 새 언어를 말해보세요.

nawana는 60초 녹음을 '유창해진 나'로 바꿉니다. 대화 상대이자 섀도잉 목표, 그리고 유창함이 손닿는 곳에 있다는 증거가 되죠. 음색과 톤, 말의 속도는 그대로 나로 남고, 바뀌는 것은 훈련하는 부분 — 언어뿐입니다.

토크 — 직접 말하며 연습
유창해진 나에게 전화를 걸어 그냥 이야기하세요. 자유 대화, 원하는 상황, 또는 내 관심사에 맞춘 뉴스로. 매 턴마다 내 문장이 유창한 내가 말했을 방식으로 되돌아옵니다 — 뜻은 같고, 더 자연스럽게. 대화가 끝나면 다섯 가지 능력으로 채점된 성적표가 나오고, 막혔던 문장은 자동으로 연습 카드가 됩니다.

워치 — 그 순간이 오기 전에 미리 살아보기
외국어에서 가장 무서운 건 '다음에 뭐라고 하지'라는 공백입니다. 다가올 실제 상황이나 내 주변 사람을 묘사하면, 유창해진 내가 바로 그 대화를 이끌어갑니다. 협상, 스몰토크, 어려운 부탁을 어떻게 풀어낼지 들어보고, 그 안의 단어와 문장을 익히세요.

섀도잉 — 그 표현을 내 것으로
문장을 이해하는 것과 내 것으로 만드는 건 다릅니다. 입이 반복해야 하니까요. 유창한 문장과 함께 소리 내어 따라 말하고, 0.5배속으로 늦추고, 막히는 단어를 반복하세요 — 단어별로 맞았는지, 바꿨는지, 건너뛰었는지 채점됩니다. 목표는 실제로 닿을 수 있는 목소리, 바로 나입니다.

리뷰 — 몸에 밸 때까지
막혔던 문장은 잊어버리기 직전에 소리 내어 답하는 드릴로 돌아옵니다 — 객관식이 아니라 직접 말하기로. 약 8,000개의 CEFR 등급 단어 풀이 바탕에 깔려 있고, 내가 쓴 단어는 자동으로 체크됩니다. 내 레벨은 실제로 사용한 단어로 추정됩니다 — 의견이 아니라 측정치입니다.

왜 내 목소리인가
원어민의 목소리는 애초에 내 것이 아니라, 아무리 흉내 내도 도달할 수 없습니다. 유창한 클론은 내 음색을 지키기에, 남은 거리는 오직 유창함 하나뿐입니다. 내 문장, 그다음 유창한 버전 — 똑같은 목소리로. 그 차이에서 들리는 모든 것이 바로 고쳐야 할 지점입니다.

소중히 다루는 내 목소리
설정할 때 60초. 내가 시작한 대화 밖에서는 절대 녹음하지 않습니다. 목소리는 언제든 다시 녹음하거나 삭제할 수 있습니다. 세션·드릴·진행 기록은 내 아이폰에 저장됩니다.

구독
하나의 구독으로 앱과 웹 모두에서. 크레딧으로 대화, 음성 생성, 섀도잉이 작동합니다. 언제든 해지할 수 있습니다.

설정 60초. 오늘 밤 첫 대화를 시작하세요.
```

### 키워드 (≤100)
```
회화연습,말하기,언어학습,섀도잉,쉐도잉,스피킹,발음,프리토킹,AI튜터,영어공부,보이스
```

> `영어회화`·`원어민`·`대화`·`목소리`·`유창`은 이름·부제가 이미 색인하므로 뺐음. 섀도잉/쉐도잉은 둘 다 실제 검색되는 표기라 병기.

### 새로운 기능 (릴리스 노트)
```
nawana 베타에 오신 걸 환영합니다.

• 60초로 내 목소리를 클론하고, 유창해진 나와 통화하며 대화 연습
• 실제 상황을 미리 살아보는 워치
• 내 목소리로 섀도잉하고 단어별로 채점
• 자동 드릴, 약 8,000단어 CEFR 단어장, 주간 리포트
• 단어·표현 홈 화면 위젯

테스트해 주셔서 감사합니다 — 피드백은 언제든 환영합니다.
```

---

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
- [ ] One Subscription Group, two tiers (Standard / Heavy)
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
