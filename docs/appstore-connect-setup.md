# App Store Connect — 구독 상품 입력 시트

> 가격의 출처는 `docs/launch-billing.md`(§1 Locked launch catalog), 상품 id의
> 출처는 DB의 `subscription_plans.apple_product_id`입니다. 이 문서는 그 둘을
> ASC 입력 화면의 **필드 단위**로 옮겨놓은 것입니다.
>
> **Product ID는 한 번 만들면 영원히 못 바꿉니다.** 오타 = 그 id는 영구 폐기.
> 아래 값을 복사해서 붙여넣으세요. 2026-08-11에 `pro_*`/`premium_*` →
> `daily_*`/`unlimited_*`로 개명했으므로 옛 이름으로 만들면 안 됩니다.

---

## 0. 먼저 — 구독 그룹 하나 만들기

6개(런칭은 4개) 상품은 **전부 같은 그룹**에 들어갑니다. 같은 그룹이어야
데일리 ↔ 무제한 전환을 Apple이 업그레이드/다운그레이드로 처리하고 일할
정산을 해줍니다. 그룹이 다르면 두 개를 동시에 구독하는 사고가 납니다.

| 필드 | 값 |
|---|---|
| Reference Name (내부용) | `nawana subscriptions` |
| Group Display Name — English | `nawana` |
| Group Display Name — 한국어 | `나와나` |

**Subscription Group Levels** (그룹 안에서의 서열 — 업그레이드 방향을 결정):

| Level | 상품 |
|---|---|
| 1 (최상위) | Unlimited Annual |
| 2 | Unlimited Monthly |
| 3 | Daily Annual |
| 4 | Daily Monthly |

무제한이 데일리보다 위여야 데일리 → 무제한 전환이 **즉시 업그레이드**로
처리됩니다. 반대로 두면 다음 갱신일까지 기다리게 됩니다.

---

## 1. 상품 4개 — 런칭 대상

### ① Daily Monthly

| 필드 | 값 |
|---|---|
| Reference Name | `Daily Monthly` |
| **Product ID** | `com.roro.futurevoice.daily_monthly` |
| Duration | 1 Month |
| Price (기준) | **€9.99** |
| Price (한국) | **₩14,000** |
| Display Name — English | `Daily Monthly` |
| Display Name — 한국어 | `데일리 월간` |
| Description — English | `5 minutes of talk a day in your own voice` |
| Description — 한국어 | `내 목소리로 하루 5분 대화` |

### ② Daily Annual

| 필드 | 값 |
|---|---|
| Reference Name | `Daily Annual` |
| **Product ID** | `com.roro.futurevoice.daily_annual` |
| Duration | 1 Year |
| Price (기준) | **€79.99** |
| Price (한국) | **₩119,000** |
| Display Name — English | `Daily Annual` |
| Display Name — 한국어 | `데일리 연간` |
| Description — English | `5 minutes of talk a day, 2 months free` |
| Description — 한국어 | `하루 5분 대화, 2개월 무료` |

### ③ Unlimited Monthly

| 필드 | 값 |
|---|---|
| Reference Name | `Unlimited Monthly` |
| **Product ID** | `com.roro.futurevoice.unlimited_monthly` |
| Duration | 1 Month |
| Price (기준) | **€19.99** |
| Price (한국) | **₩29,000** |
| Display Name — English | `Unlimited Monthly` |
| Display Name — 한국어 | `무제한 월간` |
| Description — English | `Talk as much as you want, every day` |
| Description — 한국어 | `매일 원하는 만큼 대화` |

### ④ Unlimited Annual

| 필드 | 값 |
|---|---|
| Reference Name | `Unlimited Annual` |
| **Product ID** | `com.roro.futurevoice.unlimited_annual` |
| Duration | 1 Year |
| Price (기준) | **€199.99** |
| Price (한국) | **₩299,000** |
| Display Name — English | `Unlimited Annual` |
| Display Name — 한국어 | `무제한 연간` |
| Description — English | `Unlimited talk, 2 months free` |
| Description — 한국어 | `무제한 대화, 2개월 무료` |

> Display Name은 30자, Description은 45자 제한입니다. 위 값은 모두 그 안에
> 들어갑니다. Display Name은 **설정 › Apple 계정 › 구독**에 그대로 보이는
> 이름이고, 앱의 `AccountStatus.planLabel`이 만드는 문자열("Daily Monthly")과
> 일부러 똑같이 맞췄습니다 — 앱과 설정에서 다른 이름이 보이면 해지 문의가
> 늘어납니다.

---

## 2. 무료 체험 — 상품 4개 **각각**에 설정

Introductory Offer를 상품마다 따로 만들어야 합니다. 하나라도 빠지면 그
상품만 체험 없이 즉시 결제로 뜹니다.

| 필드 | 값 |
|---|---|
| Type | **Free Trial** |
| Duration | **1 Week** (= 7일; ASC에 "7 days" 항목은 없습니다) |
| Territories | 판매하는 전 지역 |
| Eligibility | New Subscribers |

> 앱은 `product.subscription.introductoryOffer`를 읽어 체험 퍼널을 띄웁니다.
> 이게 없으면 CTA가 조용히 "Subscribe"로 바뀌고 3단계 퍼널이 통째로
> 사라집니다 — 에러는 안 나므로 눈치채기 어렵습니다.
>
> **체험 기간에는 어떤 플랜을 체험하든 하루 5분(데일리 허용량)으로 계량됩니다**
> (`20260811180000_hard_paywall_trial`). 무제한을 7일 체험하면서 하루 60분씩
> 쓰고 해지하는 걸 막기 위한 것으로, 서버에서 이미 강제됩니다.

---

## 3. 상품마다 추가로 필요한 것

| 필드 | 값 / 메모 |
|---|---|
| Review Information — Screenshot | 페이월 화면 캡처 1장 (필수) |
| Review Information — Notes | 아래 심사 노트 참고 |
| Tax Category | 기본값 (App Store 구독) |
| Family Sharing | 끔 — 음성 클론은 계정당 1개라 공유가 성립하지 않음 |
| App Store Promotion | 선택, 지금은 생략 |

**심사 노트 예시** (Review Notes에 붙여넣기):

```
Test account: <계정> / <비밀번호>
The subscription unlocks talk time with the user's own cloned voice.
Daily = 5 minutes of talk per day; Unlimited = unrestricted daily talk.
Reviewing, drills, replays and progress are free without a subscription.
The 7-day free trial is metered at the Daily allowance (5 min/day).
```

---

## 4. 주간(weekly) 상품 — 이번엔 만들지 마세요

DB에는 `daily_weekly` / `unlimited_weekly` 행이 있지만 **가격이 확정된 적이
없습니다**(`launch-billing.md`는 월간·연간만 잠갔고, 앱의 가격 맵에도
주간이 없습니다). 지금 만들면 가격을 즉석에서 정하게 되므로 런칭 후에
실험용으로 추가하세요.

앱은 이미 이에 맞춰 동작합니다 — 요금제 화면의 기간 선택기는 **실제로
구매 가능한 상품이 있는 기간만** 보여주므로(`PaywallView.availablePeriods`),
ASC에 주간이 없으면 주간 탭 자체가 안 뜹니다. 나중에 ASC에 만들면 코드
변경 없이 자동으로 나타납니다.

---

## 5. 상품 외에 반드시 함께 해야 하는 것

- [ ] **App Store Server Notifications V2** 를 `apple-webhook` 엔드포인트로 지정
      → `https://chhzjtigzdotacutwcyo.supabase.co/functions/v1/apple-webhook`
- [ ] Supabase 시크릿 `APPLE_BUNDLE_ID`, `APPLE_APP_ID` 설정 확인
- [ ] 앱 내 약관/개인정보 링크는 이미 페이월에 있음 (Apple 표준 EULA +
      `nawana.app/privacy.html`). ASC의 App Information에도 **같은** 링크를
      넣어야 합니다 — 서로 다르면 리젝 사유입니다.
- [ ] 상품 4개가 다 "Ready to Submit"이 된 뒤에 `BetaConfig.isBeta = false`
      로 내리기. **순서를 지키세요** — 먼저 내리면 하드 페이월은 막는데 팔
      상품이 없어서 신규 유저가 통화도 결제도 못 합니다.

## 6. 만든 뒤 검증 (TestFlight)

1. 새 계정으로 가입 → 통화 시도 → 페이월이 떠야 함 (무료 통화 0초)
2. 체험 시작 → DB에서 확인:
   ```sql
   select plan_id, status, trial_ends_at from user_subscriptions
    where user_id = '<uuid>';
   ```
   `status = 'trialing'` 이어야 합니다.
3. 5분 넘게 통화 → 402 `daily_cap_reached` (페이월이 아니라 "내일 다시" 문구)
4. 설정 › 구독에서 이름이 `데일리 월간` 처럼 보이는지 확인
