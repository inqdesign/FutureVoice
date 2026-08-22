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
라이트 ↔ 플러스 전환을 Apple이 업그레이드/다운그레이드로 처리하고 일할
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

플러스가 라이트보다 위여야 라이트 → 플러스 전환이 **즉시 업그레이드**로
처리됩니다. 반대로 두면 다음 갱신일까지 기다리게 됩니다.

---

## 1. 상품 4개 — 런칭 대상

> **가격 기준은 USD입니다** (2026-08-21 등록 완료 — 아래는 제안이 아니라 실제 값).
> ASC에는 USD만 넣으면 나머지 174개 스토어프론트가 자동 생성돼요. 단 **한국은 직접 지정**하세요 — 메인 마켓이고,
> 애플 환산은 Speak가 한국 기대치를 ₩29,000/₩129,000에 고정해 놨다는 걸 모릅니다.
> 그리고 **자동 갱신 구독은 애플이 나중에 재조정해 주지 않습니다.**
>
> **Product ID는 절대 못 바꿉니다** — `daily_*`/`unlimited_*`는 티어 개명 전에
> 등록된 값이고, 애플 상품 id는 앱당 영구입니다. 구매자가 읽는 건 Display Name뿐이라
> 거기만 라이트/플러스로 둡니다. Reference Name은 내부용이라 수정 가능해요.

### ① Light Monthly

| 필드 | 값 |
|---|---|
| Reference Name | `Light Monthly` |
| **Product ID** | `com.roro.futurevoice.daily_monthly` (고정) |
| Duration | 1 Month |
| Price (기준·USD) | **$9.99** |
| Price (유럽) | €9.99 — 애플 자동 |
| Price (한국) | **₩15,000** — 직접 지정 |
| Display Name — English | `Light` |
| Display Name — 한국어 | `라이트` |
| Description — English | `150 min of talk, 60 scenes a month` |
| Description — 한국어 | `한 달 통화 150분 · 상황연습 60개` |

### ② Light Annual

| 필드 | 값 |
|---|---|
| Reference Name | `Light Annual` |
| **Product ID** | `com.roro.futurevoice.daily_annual` (고정) |
| Duration | 1 Year |
| Price (기준·USD) | **$79.99** — 33% 할인 |
| Price (유럽) | €89.99 — 애플 자동 (25%) |
| Price (한국) | **₩110,000** — 직접 지정 (39%) |
| Display Name — English | `Light` |
| Display Name — 한국어 | `라이트` |
| Description — English | `150 min of talk, 60 scenes a month` |
| Description — 한국어 | `한 달 통화 150분 · 상황연습 60개` |

### ③ Plus Monthly

| 필드 | 값 |
|---|---|
| Reference Name | `Plus Monthly` |
| **Product ID** | `com.roro.futurevoice.unlimited_monthly` (고정) |
| Duration | 1 Month |
| Price (기준·USD) | **$19.99** |
| Price (유럽) | €22.99 — 애플 자동 |
| Price (한국) | **₩29,000** — 직접 지정 |
| Display Name — English | `Plus` |
| Display Name — 한국어 | `플러스` |
| Description — English | `Unlimited talk, 600 scenes a month` |
| Description — 한국어 | `통화 무제한 · 상황연습 월 600개` |

### ④ Plus Annual

| 필드 | 값 |
|---|---|
| Reference Name | `Plus Annual` |
| **Product ID** | `com.roro.futurevoice.unlimited_annual` (고정) |
| Duration | 1 Year |
| Price (기준·USD) | **$143.99** — 40% 할인 |
| Price (유럽) | €149.99 — 애플 자동 (46%) |
| Price (한국) | **₩209,000** — 직접 지정 (40%) |
| Display Name — English | `Plus` |
| Display Name — 한국어 | `플러스` |
| Description — English | `Unlimited talk, 600 scenes a month` |
| Description — 한국어 | `통화 무제한 · 상황연습 월 600개` |

> **상위 티어의 할인이 하위보다 얕으면 안 됩니다.** 플러스 40% ≥ 라이트 33%.
> 2026-08-21 이전에는 반대였고(17% vs 33%), 페이월에 `39% 절약` 옆에 `14% 절약`이
> 나란히 떠서 우리가 가장 팔고 싶은 요금제가 더 나쁜 거래로 보였습니다.
> 근거는 `docs/launch-billing.md`의 Prices 절에 있어요. |

> Display Name은 30자, Description은 45자 제한입니다. 위 값은 모두 그 안에
> 들어갑니다. Display Name은 **설정 › Apple 계정 › 구독**에 그대로 보이는
> 이름이고, 앱의 `AccountStatus.planLabel`이 만드는 문자열("Daily Monthly")과
> 일부러 똑같이 맞췄습니다 — 앱과 설정에서 다른 이름이 보이면 해지 문의가
> 늘어납니다.

---

## 2. 무료 체험 — 상품 4개 **각각**에 설정

Introductory Offer를 상품마다 따로 만들어야 합니다. 하나라도 빠지면 그
상품만 체험 없이 즉시 결제로 뜹니다.

**어디에 있나** — 별도 메뉴가 아니라 각 구독 상품 페이지 안에 있습니다:

```
App Store Connect → Apps → nawana → (좌측) Subscriptions
  → 구독 그룹 "nawana subscriptions" 선택
  → 구독 상품 4개 중 하나 선택 (예: Daily Monthly)
  → 아래로 스크롤해서 "Subscription Prices" 섹션
  → 오른쪽 [ + ] 버튼 → "Create Introductory Offer"
```

가격을 넣는 그 섹션의 `+` 안에 숨어 있어서 못 찾기 쉽습니다. 이 과정을
**상품 4개마다 반복**하세요.

| 입력 항목 | 값 |
|---|---|
| Countries or Regions | 판매하는 전 지역 선택 |
| Start Date | 오늘 (또는 출시일) |
| End Date | **No End Date** — 끝을 정하면 그날 이후 신규 가입자는 체험이 사라집니다 |
| Type | **Free** (Pay Up Front / Pay As You Go 아님) |
| Duration | **1 Week** (= 7일; ASC에 "7 days"라는 항목은 없습니다) |

**대상 지정 항목은 없습니다.** Introductory Offer는 자격이 자동으로
정해집니다 — 해당 **구독 그룹에서 체험을 한 번도 안 쓴 사람**만 받습니다.
즉 라이트 월간으로 7일 체험을 쓴 사람은 플러스 월간으로 갈아타도 다시
공짜 7일을 받지 못합니다(그룹당 1회). 4개에 모두 거는 이유는 "어느 상품을
먼저 고르든 체험이 붙게" 하기 위한 것이지, 4번 줄 수 있어서가 아닙니다.

> 앱은 `product.subscription.introductoryOffer`를 읽어 체험 퍼널을 띄웁니다.
> 이게 없으면 CTA가 조용히 "Subscribe"로 바뀌고 3단계 퍼널이 통째로
> 사라집니다 — 에러는 안 나므로 눈치채기 어렵습니다.
>
> **체험 기간에는 어떤 플랜을 체험하든 라이트 몫을 7/30로 안분해 계량됩니다**
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

**카탈로그에서도 내렸습니다** (`20260811190000_weekly_off_catalog`):
`subscription_plans`의 주간 두 행은 `is_active = false`라 앱이 아예
가져오지 않습니다. 행 자체는 남겨뒀으므로 나중에 팔고 싶어지면
**① 가격 확정 → ② ASC 상품 생성 → ③ `is_active = true`** 세 단계면 되고,
코드 수정은 없습니다. 요금제 화면의 기간 선택기가 실제 구매 가능한
상품이 있는 기간만 보여주므로(`PaywallView.availablePeriods`) 탭도
자동으로 다시 나타납니다.

---

## 5. 상품 외에 반드시 함께 해야 하는 것

- [ ] **App Store Server Notifications V2** — 애플 → **RevenueCat** → 우리
      `apple-webhook`. (2026-08-20 확정. §3의 B안: RC SDK 없음, 앱 코드 수정
      없음. RC는 결제 관리·분석 레이어이고 권한의 진실은 계속
      `user_subscriptions`입니다.)

      **① ASC** — <https://appstoreconnect.apple.com/apps/6792794655/appstore/info>
      → **App Store 서버 알림**. 프로덕션·샌드박스 **두 칸 모두** RC 주소:

      ```
      https://api.revenuecat.com/v1/incoming-webhooks/apple-server-to-server-notification/cBOtWoIwTjiZzqtkmDCyrIMkvbpEyxgw
      ```

      버전 드롭다운이 안 보이면 정상입니다(애플이 V1을 접어 신규 설정은 V2 고정).

      **② RC** — Apps → iOS 앱 → **Apple Server Notification Forwarding URL**:

      ```
      https://chhzjtigzdotacutwcyo.supabase.co/functions/v1/apple-webhook
      ```

      **이게 빠지면 결제가 우리 DB에 영영 안 들어옵니다.** RC는 애플 원본
      알림을 그대로 넘기므로 `apple-webhook`은 수정이 필요 없습니다 — 서명도
      `appAccountToken`도 원본 그대로입니다.

      **③ RC** — 같은 화면의 **"Track new purchases from server-to-server
      notifications"** 켜기. SDK를 안 쓰므로 꺼져 있으면 RC 대시보드가 빕니다.

      **④ 검증** — TestFlight 결제 한 건. `user_subscriptions`에
      `status='trialing'` 행이 생기고 `apple_original_tx_id`가 채워지면 성공.
      (2026-08-20 현재 모든 행의 그 값이 비어 있어, 값이 들어오는 순간이
      파이프라인이 처음 통과했다는 신호입니다.) RC Customers에도 같은 거래가
      보여야 ③이 제대로 켜진 겁니다.

      > 알아둘 것: 경로에 서드파티가 한 홉 늘었으므로, RC 포워딩이 어긋나면
      > 결제는 됐는데 앱은 무구독으로 봅니다. ④를 실제로 통과시키기 전까지
      > "설정했다"를 "된다"로 여기지 마세요. 그리고 SDK가 없는 동안 RC는
      > 거래는 보지만 **우리 유저가 누군지는 모릅니다**(§3 한계) — 매출 집계는
      > 정확하고, 계정 매칭이 필요해지면 그때 §4의 A안입니다.

- [x] Supabase 시크릿 `APPLE_BUNDLE_ID`(`com.roro.futurevoice`) · `APPLE_APP_ID`(`6792794655`) — 2026-08-20 설정 완료
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
4. 설정 › 구독에서 이름이 `라이트` 처럼 보이는지 확인
