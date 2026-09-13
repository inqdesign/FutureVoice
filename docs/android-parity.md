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

## 참조 버전

**앱스토어 출시 버전(1.0.1, 빌드 44)이 참조다.** 2026-09-12에 출시 브랜치를
머지했다 — 그 전까지 안드로이드 브랜치의 Swift 사본은 76커밋(그중 53개가
iOS 소스) 뒤였다. 앞으로 iOS가 움직이면 다시 머지하고 생성기를 재실행한다
(`scripts/android/gen-*.py`, 출시판과 드리프트 없음을 확인함).

**가장 큰 발견: 출시된 통화는 리얼타임 게이트웨이가 유일한 경로다**
(2026-09-05부터, 클래식 턴 루프는 iOS에서 옵션에서도 빠짐). 안드로이드는
아직 클래식 루프다. `RealtimeTalkClient.kt`를 만들었고 뷰모델 통합이
남았다.

## 현황 (2026-09-13)

| | 있음 | 전체 |
|---|---|---|
| 화면 | 65 | 75 |
| 서비스·엔진 | 80 | 95 |

## 없는 것 — 학습 루프에 닿는 순서

**루프에 직접 닿음 (먼저)**
- [x] `TalkCurriculum` — 2026-09-12. Talk 책의 Words가 학습자가 쓴 단어를
      보여주고 있었고(주울 단어가 아니라), Shadow는 미래의 나의 모든 문장을
      나열하고 있었다.
- [x] 두 언어 계약 — 2026-09-12. 처음엔 `CoachingLanguage` 파일이 없으니
      전부 빠진 줄 알았는데, 확인해 보니 요약·주간평가·큐레이션 프롬프트는
      전부 서버(엣지 함수)에 있고 거기에 이미 계약이 들어 있다. 클라이언트에
      있는 프롬프트는 통화 턴 하나뿐이었고, 거기서 `reason`에 언어 지정이
      빠져 통화 중 교정 설명이 영어로 나오고 있었다. 그 줄만 채웠다.
- [x] `FreeTalkOpeners` — 2026-09-13. 소개(9개 언어)·회전 풀·폴백 + FIRST CALL 블록,
      전부 Swift에서 추출. 요약기가 `about_user`를 흡수하고 자유 통화면 `metAt`을
      찍는다(전에는 둘 다 없어 첫 통화 소개가 영원히 반복될 구조였다).
- [x] `UtteranceTranscriber` — 리얼타임에선 해당 없음: 게이트웨이의 `user_turn`이
      이미 오디오 기반 전사다(Gemini Live). 클래식 경로 전용이었다.
- [ ] `PracticeStats` — 스트릭과 통계 엔진.
- [x] `SavedLineStore` — 2026-09-13. iOS 같은 파일·형태. 저장 목록은 브라우저 상단
      SAVED 섹션으로(iOS의 SavedLinesView는 진입점이 없었다).
- [ ] `LocalAlignment` — 샤도잉 리듬 점수. **보류**: Apple 인식기의 단어별 타임스탬프에
      기대는 구현이라 안드로이드 SpeechRecognizer로는 같은 값을 얻을 수 없다. 리듬
      점수 없이도 매치 점수는 나온다.

**통화 경험**
- [x] `CallNowPlaying` → 포그라운드 서비스(`CallForegroundService`, 마이크·미디어 타입)
      2026-09-13. 알림이 잠금화면 제어(일시정지/재개·끊기). 에뮬레이터 검증: 통화 중
      화면을 꺼도 35초 뒤 게이트웨이 stats가 계속 도착.
- [x] `RealtimeTalkClient` — **출시된 유일한 통화 경로.** 2026-09-13 통합, 에뮬레이터 검증:
      접속(`ready`) → 게이트웨이가 오프너 발화 → 세션 유지(stats) → 게이트웨이 유휴(3분, 전사
      인터림으로 재무장)는 PAUSED → 전사 탭·알약 탭 양쪽으로 재접속(`ready`) → End 정리.
      벽 매핑: 소진/한도/fair-use(확인 중). 네이티브 크래시 둘(AudioTrack 동시 쓰기,
      AudioRecord read 중 release) 수정. **실기기에서만 볼 수 있는 것:** 진짜 마이크의
      사용자 턴과 교정 요청, 스피커 에코 제거·끼어들기(VOICE_COMMUNICATION AEC),
      블루투스 경로, 잠금화면.

**사람·복습 주변**
- [x] `CounterpartDetailView` / `CounterpartVoiceIntakeView` — 2026-09-13. 내 사람 카드(프로필 섹션·상황
      아이디어(`CounterpartIdeas`, 프롬프트·폴백은 `gen-counterpart-ideas.py`로 리프트)·이 사람과의
      장면·Edit). Find people 상단에 iOS처럼 "Your people" 섹션(새 사람·행→카드). 저장 시나리오
      타입을 iOS와 같은 title+blurb로 교정. 음성 인테이크(받아쓰기 파싱)는 `PersonaParser` 쪽에 이미 있음.
      목소리 인테이크
- [x] `ShadowBrowserSheet` — 2026-09-13. 통화별 미래의 나 문장 전부, 줄마다 북마크,
      탭하면 샤도잉. Practice 샤도잉 타일의 All로 진입(iOS allCount/all).
- [ ] `ScenarioBuilderSheet`, `ScenarioIdeaCache`
- [x] `CommonGround` — 2026-09-13. 겹치는 지점을 코드로 먼저 계산(같은 도시·같은 관심사·같은
      또래의 아이·둘 다 배우는 중)해서 통화(낯선 사람)와 장면 프롬프트에 넣는다. 장면은
      서버가 메시지를 만드는 쪽이라 `common_ground` 필드를 **추가**로 받게 하고 배포함 — 안 보내면
      예전 그대로라 iOS엔 영향 없음.
- [ ] `WatchDialogueStore`, `BookGlossary`, `LearnerAddress`
- [ ] `ScenarioBuilderSheet`, `ScenarioIdeaCache`
- [x] `FeedbackSheet` — 2026-09-13. 첫 통화 Done·첫 장면 완주 뒤 한 번, `beta_reviews`에 같은 행.
- [x] `VoiceComparisonSheet` — 2026-09-13. Me → "Doesn't sound like you?"(녹음 vs 클론, 같은 문장, 클론
      쪽은 fidelity 모델로 한 번 합성해 디스크 캐시) + "Re-record voice" 행과 확인 → 같은 클론 플로우로
      재녹음(`recloning`). 온보딩 Meet 단계 안의 비교 진입은 아직 없음.
- [ ] ~~`HistorySheet`~~ — iOS에서 아무 데도 안 쓰임(죽은 파일), N/A.
- [ ] ~~`LevelHeader`~~ — iOS에서 삭제됨, N/A.
- [x] `ReferralJoinSheet` — 2026-09-13. 포그라운드에서 `referral_redemptions`를 폴링, 첫 실행은
      조용히 기준점만, 새 합류는 무음 로컬 알림 + 시트. **미검증**: 다른 계정이 코드를
      써야 흐름이 보인다.
- [ ] `LevelEqualizer`, `LevelHeader`

**알림·계측**
- [x] `Analytics` — 2026-09-13. SDK 없이 PostHog capture API, iOS와 같은 프로젝트·이벤트
      이름·대문자 UUID distinct_id, DEBUG 옵트아웃. 1차: conversation_started/ended,
      setup_completed, level_up, shadow_attempted. 2차: voice_clone_started/succeeded/failed, screen_viewed, word_saved/known,
      drill_reviewed, expression_bookmarked, daily_call_scheduled, voice_accent_applied,
      voice_consent_given, language_added/switched, onboarding_started. **남은 것**:
      daily_call_answered, drill_used_in_conversation, voice_accent_previews_requested,
      audio_played(출처별, 통화는 iOS처럼 제외). 남은 것과 이유: daily_call_declined/missed는
      데일리 콜 v2(결과·콜백)가 없어 붙일 상태가 없음; drill_snoozed는 안드로이드에선
      `fileInBin`이 그 동작이라 drill_reviewed에 포함; expression_dismissed·
      voice_accent_removed는 그 동작 자체가 아직 없음; widget_opened는 위젯 없음(N/A).
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
