# RevenueCat 연동 가이드

> 대상: `com.roro.futurevoice` / RC는 **결제 관리 레이어**이고, 이 앱의
> 권한 판정은 지금도 앞으로도 **Supabase `user_subscriptions` 행**입니다.
> RC를 넣어도 서버 계량(`consume_metered_seconds` → 하루 허용량)은 한 줄도
> 바뀌지 않습니다. RC는 "누가 구독 중인가"를 알려주는 소식통일 뿐입니다.

---

## 0. 먼저 결정 — 지금 필요한가?

**현재 구조는 이미 완성돼 있고 작동합니다:**

```
앱(StoreKit 2 직접) ──구매──> Apple
                                 │  Server Notifications V2
                                 ▼
                        supabase/functions/apple-webhook
                                 │ upsert
                                 ▼
                          user_subscriptions  ← 권한의 진실
```

RC가 주는 것: 크로스플랫폼(안드로이드/웹 통합), 환불·유예기간·결제실패
처리, 구독 분석 대시보드, 영수증 검증 유지보수 제거. **RC가 주지 않는 것**:
이 앱의 하루 허용량 계량. 그건 우리 DB 몫으로 남습니다.

RC 도입에는 두 갈래가 있고, **이번 주 런칭이면 B를 강력히 권합니다.**

| | A. 전면 도입 | B. 알림 포워딩만 (권장) |
|---|---|---|
| 앱 코드 | `StoreKitService` 구매/복원을 RC SDK로 교체 | **그대로** |
| SPM 의존성 | `purchases-ios` 추가 필요 | **불필요** |
| 서버 | `revenuecat-webhook` 새로 작성 | **기존 `apple-webhook` 그대로** |
| Apple 알림 | RC로 감 → RC가 우리에게 포워딩 | RC로 감 → RC가 우리에게 포워딩 |
| 리스크 | 결제 경로 전체가 새 코드 | 거의 없음 |
| 얻는 것 | RC 대시보드 + 크로스플랫폼 + 자동 처리 | RC 대시보드(분석) |

> ⚠️ A안은 `CLAUDE.md`의 "SPM deps: supabase-swift only. Add more only with
> a concrete need" 규칙을 깨는 결정입니다. 깨도 되지만 의식적으로 하세요.
>
> **B로 시작해서 RC 데이터가 쌓이는 걸 보고, 안드로이드나 웹 결제를 실제로
> 만들 때 A로 넘어가는 게 순서상 안전합니다.** Apple 알림이 RC를 거쳐
> 우리에게 오므로, 나중에 A로 가도 `user_subscriptions` 스키마는 그대로입니다.

---

## 1. RC 대시보드 — 프로젝트와 앱 (A·B 공통)

1. RevenueCat 가입 → **Create new project** → 이름 `nawana`
2. 프로젝트 안에서 **Apps → + New → App Store**
3. **App bundle ID**: `com.roro.futurevoice`

### Apple 자격증명 등록

RC가 애플 영수증을 검증하려면 아래가 필요합니다. ASC에서 발급해 RC 앱
설정 화면에 붙여넣습니다.

| 항목 | 발급 위치 | 용도 |
|---|---|---|
| **In-App Purchase Key (.p8)** | ASC → Users and Access → Integrations → **In-App Purchase** → `+` | StoreKit 2 영수증 검증 (필수) |
| Key ID / Issuer ID | 위와 같은 화면 | .p8과 함께 입력 |
| **App-Specific Shared Secret** | ASC → 앱 → General → App Information → App-Specific Shared Secret | 구버전 영수증 검증 (권장) |
| App Store Connect API Key | ASC → Users and Access → Integrations → App Store Connect API | 상품 자동 임포트(선택) |

> .p8 파일은 **다운로드 한 번뿐**입니다. 잃어버리면 키를 새로 만들어야 합니다.

---

## 2. 상품 · Entitlement · Offering 매핑

### Products (4개 임포트)

ASC API Key를 연결했다면 자동으로 들어오고, 아니면 수동으로 추가합니다.

```
com.roro.futurevoice.daily_monthly
com.roro.futurevoice.daily_annual
com.roro.futurevoice.unlimited_monthly
com.roro.futurevoice.unlimited_annual
```

### Entitlements (2개)

이 앱은 티어마다 **하루 허용량이 다르므로**(데일리 300초 / 무제한 3600초)
entitlement를 하나로 합치면 안 됩니다. 반드시 2개:

| Entitlement ID | 붙일 상품 | 서버의 대응 |
|---|---|---|
| `daily` | daily_monthly, daily_annual | `subscription_plans.daily_seconds = 300` |
| `unlimited` | unlimited_monthly, unlimited_annual | `daily_seconds = 3600` |

### Offerings (1개)

| Offering | Package | 상품 |
|---|---|---|
| `default` (Current) | `$rc_monthly` | daily_monthly |
| | `$rc_annual` | daily_annual |
| | `unlimited_monthly` (커스텀) | unlimited_monthly |
| | `unlimited_annual` (커스텀) | unlimited_annual |

> B안(포워딩만)에서는 Offering을 안 써도 됩니다 — 앱이 여전히 DB의
> `subscription_plans`에서 목록을 읽기 때문입니다. A안으로 갈 때 필요합니다.

---

## 3. B안 — Apple 알림 포워딩 (앱 수정 없음) ⭐

**이게 이번 주에 할 일 전부입니다.**

### 3-1. ASC의 알림 URL을 RC로 변경

```
App Store Connect → 앱 → General → App Information
  → App Store Server Notifications
  → Production Server URL / Sandbox Server URL 에
    RC 대시보드가 알려주는 URL을 입력
```

RC 앱 설정 화면의 *Apple Server-to-Server Notification* 섹션에 우리가 넣을
URL이 표시됩니다.

### 3-2. RC가 우리 웹훅으로 포워딩하게 설정

```
RC Dashboard → Apps → (iOS 앱) → 아래로 스크롤
  → "Apple Server Notification Forwarding URL" 에 입력:

  https://chhzjtigzdotacutwcyo.supabase.co/functions/v1/apple-webhook
```

이렇게 하면 애플 → RC → 우리 `apple-webhook` 순으로 원본 알림이 그대로
전달되어, **기존 서버 코드가 아무 수정 없이 계속 동작합니다.**

### 3-3. 새 구매를 RC가 즉시 추적하게

```
RC Dashboard → 앱 설정 → "Track new purchases from
server-to-server notifications" 켜기
```

기본값은 꺼짐이고, 꺼져 있으면 RC SDK로 결제한 것만 대시보드에 잡힙니다.
우리는 SDK를 안 쓰므로(B안) **반드시 켜야** RC에 데이터가 쌓입니다.

### 3-4. 검증

TestFlight에서 결제 → 다음 두 곳에 모두 나타나야 합니다.

```sql
-- 우리 DB (권한의 진실)
select plan_id, status, trial_ends_at, current_period_end
  from user_subscriptions where user_id = '<uuid>';
```

RC 대시보드 → Customers 에서 같은 거래가 보이면 성공입니다.

> B안의 한계: RC는 **거래는 보지만 우리 유저 ID는 모릅니다**(SDK를 안 쓰니
> app_user_id가 익명). 대시보드 매출 집계는 정확하지만 "이 구독자가 우리
> 어느 계정인지"는 RC 쪽에서 알 수 없습니다. 그게 필요해지면 A안입니다.

---

## 4. A안 — SDK 전면 도입 (나중에)

### 4-1. 의존성

`project.yml`의 packages에 추가 후 `xcodegen generate`:

```yaml
packages:
  RevenueCat:
    url: https://github.com/RevenueCat/purchases-ios
    from: 5.0.0
```

### 4-2. API 키

RC의 **public SDK key**(`appl_...`)는 앱에 담겨도 되는 키지만, 이 저장소
규칙대로 `Config/FutureVoice.xcconfig`(gitignore됨)를 통해 주입하고
`.example`에는 빈 칸만 둡니다.

```
REVENUECAT_API_KEY =
```

### 4-3. 설정 — `AppDelegate.didFinishLaunchingWithOptions`

`StoreKitService.startTransactionListener()`와 **둘 다 두면 안 됩니다.**
RC SDK가 트랜잭션 큐를 직접 관리하므로, A안으로 가면 우리 리스너는
제거해야 이중 `finish()`가 나지 않습니다.

```swift
Purchases.logLevel = .info
Purchases.configure(
    with: Configuration.Builder(withAPIKey: Secrets.revenueCatAPIKey)
        .with(storeKitVersion: .storeKit2)
        .build()
)
```

### 4-4. 유저 ID 연결 — 이게 A안의 핵심

RC의 `app_user_id`가 **Supabase user id와 같아야** 웹훅이 어느 계정인지
알 수 있습니다. 익명 ID로 두면 웹훅이 와도 매칭이 불가능합니다.

```swift
// 로그인 직후 (AuthService의 세션 확립 지점)
_ = try? await Purchases.shared.logIn(session.user.id.uuidString)

// 로그아웃 시
_ = try? await Purchases.shared.logOut()
```

### 4-5. 구매 · 복원 교체

| 지금 | RC |
|---|---|
| `product.purchase(options: [.appAccountToken(...)])` | `Purchases.shared.purchase(package:)` |
| `AppStore.sync()` | `Purchases.shared.restorePurchases()` |
| `sub.isEligibleForIntroOffer` | `Purchases.shared.checkTrialOrIntroDiscountEligibility(product:)` |

`appAccountToken`은 더 이상 필요 없습니다 — 4-4의 `logIn`이 그 역할을
대신합니다.

### 4-6. RC 웹훅 → 우리 서버

```
RC Dashboard → Integrations → Webhooks → + New
  URL: https://chhzjtigzdotacutwcyo.supabase.co/functions/v1/revenuecat-webhook
  Authorization header: <임의의 긴 랜덤 문자열>
```

그 문자열을 `supabase secrets set REVENUECAT_WEBHOOK_SECRET=...` 로 넣고,
새 함수에서 헤더를 비교해 인증합니다(RC는 서명 대신 이 방식입니다).
`supabase/config.toml`에 `verify_jwt = false` 필요.

**이벤트 → `user_subscriptions.status` 매핑:**

| RC event.type | status | 비고 |
|---|---|---|
| `INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION` | `active` | `period_type == "TRIAL"` 이면 **`trialing`** |
| `CANCELLATION` | 변경 없음 | `cancel_at_period_end = true` 만 세팅 (기간 끝까지 유효) |
| `EXPIRATION` | `expired` | |
| `BILLING_ISSUE` | `grace` | |
| `PRODUCT_CHANGE` | 유지 | `plan_id`만 새 상품으로 |
| `SUBSCRIPTION_PAUSED` | `expired` | |

**주의점 3가지:**

1. `plan_id`는 `event.product_id`로 **`subscription_plans`를 조회**해서
   얻으세요(`apple_product_id` 컬럼과 조인). 문자열을 자르지 마세요 —
   상품 id 규칙이 바뀌면 조용히 깨집니다.
2. `period_type == "TRIAL"` 을 반드시 `status = 'trialing'` 으로 옮겨야
   합니다. 서버가 체험을 **하루 5분**으로 계량하는 근거가 이 값입니다
   (`20260811180000_hard_paywall_trial`).
3. **크레딧을 지급하지 마세요.** 분 네이티브 모델에서 구독 행 자체가
   권한이고, 갱신 시 지급은 없습니다.

기존 `apple-webhook/index.ts`가 그대로 참고 구현입니다 — 상태 매핑과
upsert 로직을 거의 복사할 수 있습니다.

---

## 5. 어느 쪽이든 바뀌지 않는 것

- `consume_metered_seconds` — 하루 허용량 계량. RC는 여기 관여하지 않습니다.
- 402 두 종류: `insufficient_credits`(페이월) / `daily_cap_reached`(내일 다시)
- 하드 페이월: 신규 가입 0초
- 체험 = 하루 5분 (플랜 무관)
- `subscription_plans.daily_seconds` 가 허용량의 유일한 출처

RC를 나중에 걷어내도 위는 전부 그대로입니다. 그게 이 구조를 이렇게 짠
이유입니다 — 결제 대행사는 갈아탈 수 있어야 합니다.
