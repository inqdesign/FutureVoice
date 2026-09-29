# Play Console — 스토어 등록 준비 (2026-09-29)

ASC 쪽 `fastlane/metadata/` + `scripts/asc-submit.py`의 안드로이드 짝.
**API로 쓰는 것**과 **콘솔에서 손으로 넣는 것**이 나뉜다. 손으로 넣는 칸은
전부 아래에 붙여 넣을 답으로 적어 두었다.

## 1. API로 쓰는 것 — `scripts/android/play-listing.py`

| 무엇 | 파일 |
|---|---|
| 앱 이름(30) · 간단한 설명(80) · 자세한 설명(4000) | `android/fastlane/metadata/android/<언어>/` |
| 새로운 기능(500) — 첫 출시분 | `<언어>/changelogs/1.txt` (트랙 출시에 실림, 배포 스크립트 7.5가 읽음) |
| 연락처 이메일 · 웹사이트 · 기본 언어 | `contact_email.txt` · `contact_website.txt` · `default_language.txt` |
| 아이콘 512 · 그래픽 이미지 1024×500 | `en-US/images/` (모든 언어 공통) |
| 휴대전화 스크린샷 | `<언어>/images/phoneScreenshots/` |

언어: en-US · en-GB(en-US 공유) · ko-KR · ja-JP · zh-TW · zh-CN · es-ES ·
es-419(es-ES 공유) · fr-FR. **de-DE는 뺐다** — 안드로이드 앱에 독일어 UI가
아직 없어서, 독일어 페이지는 없는 화면을 약속하게 된다. `values-de`가 생기면
iOS `fastlane/metadata/de-DE/`를 같은 방식으로 옮기고 `LOCALES`에 한 줄.

iOS 문구에서 바꾼 것: `iPhone` → 휴대폰, 섀도잉의 0.5배속(안드로이드에 없음)
→ "걸리는 구간만 골라 연습", Apple 이용약관 링크 → `nawana.app/terms.html`,
구독 문단에 **처음 20분 무료**와 **Google Play 자동 갱신** 한 줄, 매일 전화
단락 추가. (iOS en-US 설명의 구독 문단은 "Plus"가 빠져 문장이 깨져 있다 —
안드로이드판은 고쳐 썼고, iOS는 다음 제출 때 같이 고칠 것.)

```bash
scripts/android/play-listing.py                   # 파일 검사 + 계획
scripts/android/play-listing.py --images          # 그림까지 검사
scripts/android/play-listing.py --send --images   # 실제로 쓰기
```

**키가 있어야 돈다**: Google Cloud 서비스 계정 JSON을
`~/keys/play-service-account.json`에 두고, Play Console → 사용자 및 권한에
그 계정 이메일을 초대("스토어 등록정보 관리" + 출시 관리). 앱이 콘솔에 먼저
만들어져 있어야 한다(API는 앱을 만들지 못한다). 첫 출시 전의 초안 앱에서
커밋이 거절되면 `--not-for-review`를 붙인다.

## 2. 앱 만들기 (콘솔, 한 번)

- 앱 이름: `nawana: Language Learning` · 기본 언어 영어(미국) · **앱** · **무료**
  (구독은 인앱 상품이라 "무료"가 맞다)
- 패키지 `com.roro.futurevoice` — 첫 AAB 업로드 때 정해진다. **Play 앱 서명**
  사용, 업로드 키는 `~/keys/nawana-upload.jks`(서명 설정은 `local.properties`).
- 카테고리: **교육** · 태그: 언어 학습, 교육
- 연락처: hello.dearroroapp@gmail.com · https://nawana.app

## 3. 앱 콘텐츠 — 붙여 넣을 답

### 개인정보처리방침
`https://nawana.app/privacy.html` — **단, 지금 페이지는 iOS만 말한다**
(Apple ID 로그인, 아이폰에 저장, Apple 결제). 심사관은 방침과 앱을 대조하므로
출시 전에 Google 로그인 · Google Play 결제 · Android를 넣어야 한다. 5절 참고.

### 광고
**아니요.** 광고 SDK 없음.

### 앱 액세스
"일부 기능이 제한됨"을 고르고:
> Sign in with Google (any Google account) or Apple. Onboarding asks for
> microphone permission, a 16+ age confirmation, a separate voice-cloning
> consent, and a 60-second recording before the app unlocks. The voice clone
> and the first 20 minutes of talk are free; after that a subscription is
> needed.

⚠️ 결정 필요: 심사관이 20분 뒤 구독 화면에 막힌다. 구독 기능까지 보게 하려면
**심사용 계정을 하나 만들어 무료 구독(comp)을 걸고** 이메일/비밀번호를 이 칸에
넣는 게 안전하다. 그런데 릴리스 빌드엔 이메일 로그인이 없다(개발 빌드 전용) —
그러면 심사용 Google 계정을 만들어 그 계정에 comp를 거는 방식이 된다.
또 **Google 로그인은 7.2(OAuth 클라이언트 ID)가 끝나야 버튼이 뜬다.**

### 콘텐츠 등급 (IARC 설문)
- 카테고리: **참고, 뉴스 또는 교육** 류(게임 아님)
- 폭력·성·욕설·약물·도박: 전부 **아니요**
- 사용자 간 상호작용/콘텐츠 교환: **아니요** — Find people의 상대는 AI가
  연기하는 인물이고, 메시지가 상대 사용자에게 전달되지 않는다.
- 사용자 정보를 다른 사용자와 공유: **예** — Find people에 공개하면 이름·직업·
  사는 곳·관심사가 같은 언어 학습자에게 보인다(사용자가 직접 공개할 때만).
- 위치 공유: **아니요** (사는 곳은 직접 쓴 텍스트, 기기 위치 아님)
- 디지털 상품 구매: **예** (구독)
- AI 생성 콘텐츠를 묻는 문항이 나오면 **예** — 대화 상대의 말과 교정이 생성형 AI.

### 타겟층
**16–17세, 18세 이상**만 체크. 이용약관·방침이 16세 이상(음성 복제 = 생체정보,
독일 디지털 동의 연령)이고 온보딩에서 연령을 확인한다. 13세 미만을 고르지
않으므로 가족 정책 대상 아님. "아동의 관심을 끌 수 있음": **아니요**.

### 뉴스 앱
**아니요.** 관심사 뉴스로 대화 주제를 고르는 기능은 있지만 뉴스를 발행하지 않는다.

### 정부 앱 · 금융 기능 · 건강 앱
전부 **아니요.**

### 계정 삭제
- 앱 안: **Me → Delete account** (`AccountEraser.deleteAccount`)
- 웹 URL: `https://nawana.app/delete-account.html` — 새로 만든 페이지(5절).
  Play는 앱을 지운 사람도 삭제를 요청할 수 있는 웹 경로를 요구한다.
- 일부 데이터만 삭제 요청: **예** — Me → Privacy에서 음성 동의 철회 = 목소리만 삭제.

### 데이터 보안 (Data safety)
공통: 전송 중 암호화 **예** · 삭제 요청 가능 **예** · 모든 사용자 데이터가
수집되는가 **예**. 우리 대신 처리하는 곳(Supabase, ElevenLabs, Google Gemini,
PostHog)은 Play 정의상 "서비스 제공업체"라 **공유 아님**. 기기에만 남는 것
(대화 기록·카드·단어·진행, 인물 사진, 하루 카드 사진)은 **수집 아님**.

| 데이터 유형 | 수집 | 공유 | 필수/선택 | 목적 | 비고 |
|---|---|---|---|---|---|
| 개인 정보 › 이메일 주소 | 예 | 아니요 | 필수 | 계정 관리, 앱 기능 | Google/Apple 로그인 |
| 개인 정보 › 사용자 ID | 예 | 아니요 | 필수 | 계정 관리, 분석 | Supabase 계정 UUID(PostHog `distinct_id`) |
| 개인 정보 › 이름 | 예 | 아니요 | 선택 | 앱 기능 | 표시 이름 — Find people 공개는 사용자가 직접 |
| 개인 정보 › 기타 정보 | 예 | 아니요 | 선택 | 앱 기능 | 직업·사는 곳·관심사(프로필, 공개 시 다른 학습자에게) |
| 위치 › 대략적인 위치 | 예 | 아니요 | 필수 | 분석 | PostHog가 IP로 도시를 추정 |
| 금융 정보 › 구매 기록 | 예 | 아니요 | 필수 | 앱 기능, 계정 관리 | 구독 상태를 서버에 보관 |
| 오디오 › 음성 또는 녹음 | 예 | 아니요 | 필수 | 앱 기능 | 60초 클론 샘플(ElevenLabs, 원본 24시간 보관), 대화 턴 오디오(전사용, **일시적 처리 예**) |
| 앱 활동 › 앱 상호작용 | 예 | 아니요 | 필수 | 분석 | 손으로 쓴 이벤트만, 자동 수집·화면 녹화 없음 |
| 앱 활동 › 기타 사용자 생성 콘텐츠 | 예 | 아니요 | 필수 | 앱 기능 | 대화 텍스트·상황 설명을 Gemini로 보냄(보관 안 함) |
| 앱 정보 및 성능 › 비정상 종료/진단 | 예 | 아니요 | 필수 | 분석 | 통화 실패 기록(`client_events`: 오디오 경로·오류 코드) |

해당 없음: 연락처, 캘린더, 사진·동영상(기기에만), 파일(안드로이드에 상황 자료
첨부 없음 — 이식되면 "파일 및 문서" 추가), 건강, 웹 기록, 기기 ID(광고 ID·
ANDROID_ID 안 씀).

### 권한 선언 (targetSdk 36이라 심사에서 걸리는 것)
- **포그라운드 서비스** `microphone|mediaPlayback` — 콘솔의 "포그라운드 서비스
  권한" 양식에 용도와 **동영상 링크**가 필요:
  > The user starts a voice call with their practice partner. The call keeps
  > listening to the microphone and playing the partner's voice while the
  > screen is locked or the user switches apps, and can be ended from the
  > notification. It stops when the call ends.
  동영상: 실기기에서 통화 시작 → 화면 잠금 → 알림에서 끊기, 30초 정도. (사장님 폰)
- **USE_FULL_SCREEN_INTENT** — Android 14부터 Play는 **핵심 기능이 알람이나
  전화인 앱**에만 허용한다. 매일 전화(정한 시각에 울리는 통화)로 "전화/알람"
  선언을 하되, **거절될 수 있다.** 거절되면 권한이 없을 때 일반 알림으로
  떨어지는지 먼저 확인할 것(iOS의 알림 폴백과 같은 모양).
- **SCHEDULE_EXACT_ALARM** — 선언 양식은 없지만 Android 14+에서 기본 거부.
  사용자가 설정에서 허용해야 매일 전화가 정시에 울린다.

## 4. 결제 상품 (7.1)
구독 2개(Light·Plus, 월간) — 연간은 iOS에서 판매 중지(2026-09-26)라 만들지
않는다. 100분 팩도 iOS에서 판매 안 함. 상품 ID를 정하면
`subscription_plans.google_product_id`를 채운다. 가격은 iOS 표
(`docs/launch-billing.md` 2026-09-26)와 같게.

## 5. 웹 페이지 (iOS 저장소 `web/`, 배포는 사람이)
- `delete-account.html` / `delete-account-ko.html` — Play 계정 삭제 URL용, 새로 씀.
- `privacy.html` / `privacy-ko.html` — Google 로그인·Google Play 결제·Android
  저장을 넣어야 함. **법적 문구라 사장님 확인 뒤 반영.**
- `terms.html` — "Sign-in is through Apple", 결제 조항이 Apple/Stripe뿐. Google Play 추가 필요.
- `support.html` — iPhone·Apple 전제. Android 절 필요.

## 6. 남은 것 (사장님 쪽)
1. Play Console에 앱 만들기 + 서비스 계정 초대 → 키를 `~/keys/`에
2. 7.2 Google OAuth 클라이언트 ID (없으면 로그인 버튼이 안 뜬다 — 심사 불가)
3. 7.1 구독 상품
4. 위 3절 양식들, 포그라운드 서비스 동영상
5. 웹 방침·약관 문구 확인 → 배포
6. 그래픽 이미지 초안 확인(`en-US/images/featureGraphic.png`)
   스크린샷(7개 언어 × 5장, 캡처 하네스 `home`·`watchtab`·`talkdetail`·`vocab`·`progress`,
   1080×2156로 시스템 바 잘라냄): UI는 각 언어지만 **샘플 데이터는 영어** — 점수 한 줄
   평은 코칭이라 원래 모국어여야 하고, 홈 뉴스 카드가 OpenAI를 이름으로 든다. 언어별
   시드를 하네스에 넣을지, 이대로 올릴지 결정. es·fr 성장 화면은 다섯째 칩이 잘려 보인다.
7. **런처 아이콘**: 안드로이드 앱 아이콘이 아직 임시 마이크 그림이다. iOS의
   픽셀 마크로 바꿀지(→ 스토어 아이콘과 일치) 결정. 스토어 아이콘은 이미 픽셀 마크.
