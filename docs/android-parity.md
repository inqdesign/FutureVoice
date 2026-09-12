# 안드로이드 패리티 현황

iOS를 그대로 안드로이드로 옮기는 작업의 **스콥과 진행 상황**. 숫자는
2026-09-12에 실제로 세어서 넣었고, 갱신할 땐 다시 세고 날짜를 바꾼다.

## 세는 법과 그 한계

iOS의 화면·서비스 하나하나에 대응하는 안드로이드 구현이 **있는지**를
센다. 있다고 해서 **작동한다는 뜻은 아니다** — 눌러본 것 중 셋이 있는데
닿지 않거나 깨져 있었다:

- 샤도잉: 타일이 선반만 바꾸고 세션을 열지 않음(목표 `0/2`를 채울 길이
  없었다)
- Watch의 저장된 시나리오: Talk 버튼이 달려 Watch가 Talk 탭 일을 하고 있었음
- 하루 카드: 시트가 절반만 열려 카드가 잘림

그래서 **"있음" 비율은 완성도를 과대평가한다.** 화면을 눈으로 보는 것과
눌러서 도착하는지 확인하는 것은 다른 작업이고, 후자는 아직 일부만 했다.

## 현황 (2026-09-12)

| | 있음 | 전체 |
|---|---|---|
| 화면 | 59 | 75 |
| 서비스·엔진 | 71 | 95 |

## 없는 것 — 학습 루프에 닿는 순서

**루프에 직접 닿음 (먼저)**
- [x] `TalkCurriculum` — 2026-09-12. Talk 책의 Words가 학습자가 쓴 단어를
      보여주고 있었고(주울 단어가 아니라), Shadow는 미래의 나의 모든 문장을
      나열하고 있었다.
- [ ] `CoachingLanguage` — 모든 코칭 프롬프트가 끼워 넣는 두 언어 계약
      (재료는 목표 언어, 설명은 모국어). 없으면 설명이 영어로 돌아온다.
- [ ] `FreeTalkOpeners` — 첫 인사를 번들에서 꺼내 Gemini를 기다리지 않는
      다. 첫 통화 소개(FIRST CALL)도 여기에 걸려 있다.
- [ ] `UtteranceTranscriber` — 턴당 두 번째 호출(오디오 기반 전사).
      지금은 인식기 결과만 쓴다.
- [ ] `PracticeStats` — 스트릭과 통계 엔진.
- [ ] `SavedLineStore` / `SavedLinesView` — 저장한 문장.
- [ ] `LocalAlignment` — 샤도잉 리듬 점수.

**통화 경험**
- [ ] `CallNowPlaying` — 잠금 화면에서 통화를 제어. 없으면 잠근 폰에서
      끊을 방법이 없다.
- [ ] `RealtimeTalkClient` — 실시간 통화 경로.

**사람·복습 주변**
- [ ] `CounterpartDetailView` / `CounterpartVoiceIntakeView` — 상대 상세와
      목소리 인테이크
- [ ] `ShadowBrowserSheet` — 전체 샤도잉 목록(손패의 대안)
- [ ] `ScenarioBuilderSheet`, `ScenarioIdeaCache`
- [ ] `WatchDialogueStore`, `CommonGround`, `BookGlossary`, `LearnerAddress`
- [ ] `HistorySheet`, `FeedbackSheet`, `VoiceComparisonSheet`
- [ ] `ReferralJoinSheet` — 친구가 들어왔을 때 알림
- [ ] `LevelEqualizer`, `LevelHeader`

**알림·계측**
- [ ] `Analytics` — 계측이 전혀 없다. 출시 후 무슨 일이 일어나는지 모른다.
- [ ] `DrillReminder` / `ItemReminder` / `TrialReminder` / `ReviewNotifications`
- [ ] `UILanguage` — 앱 언어 해석
- [ ] `AvatarStore`, `VoiceSampleStore`, `MicChoiceSheet`, `UsageDetailView`
- [ ] `UpdateAvailableSheet` — iOS 전용 개념(Play는 인앱 업데이트가 따로)

## iOS와 다른 것이 맞는 자리

여기 있는 것들은 "안 한 것"이 아니라 **플랫폼이 달라서 다른 것**이다.

- 정확 알람: `USE_EXACT_ALARM`은 Play가 알람·시계 앱에만 허용 →
  `SCHEDULE_EXACT_ALARM` + 부정확 폴백
- 결제: StoreKit → Play Billing (`google-webhook`, `google_product_id`)
- Apple 제품 id는 그대로 두고 Play 상품을 따로 만든다

## 사장님 쪽 (제가 못 하는 것)

- [ ] Play Console 구독 상품 4개 → 만들어지면 `google_product_id`를 채운다
- [ ] Google OAuth 클라이언트 ID → 없으면 구글 로그인 버튼이 숨겨진다
- [ ] RTDN(Pub/Sub) 토픽 → 웹훅은 배포됨
