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
- [x] `CommonGround` — 2026-09-13. 겹치는 지점을 코드로 먼저 계산(같은 도시·같은 관심사·같은
      또래의 아이·둘 다 배우는 중)해서 통화(낯선 사람)와 장면 프롬프트에 넣는다. 장면은
      서버가 메시지를 만드는 쪽이라 `common_ground` 필드를 **추가**로 받게 하고 배포함 — 안 보내면
      예전 그대로라 iOS엔 영향 없음.
- [x] `BookGlossary` — 2026-09-13. 내보낸 책 뒤에 용어집: 책이 가르치는 단어·표현마다 품사·뜻·예문
      하나. 사전은 이미 공유 테이블에 있어(`WordLore`) 대개 캐시 읽기로 끝나고, 8초 예산과 40개
      상한 안에서만 찾는다 — 느린 사전이 용어집을 잃을 수는 있어도 책을 막을 수는 없다.
      에뮬레이터에서 마크다운 내보내기로 확인.
- [ ] `WatchDialogueStore`, `LearnerAddress`
- [x] `ScenarioBuilderSheet` / `ScenarioIdeaCache` — 2026-09-13. 컴포저가 카테고리 → 좁히기 → 구체적
      상황으로 내려간다. 1단계는 배송된 시드(왕복 0), 그 아래는 모델이 쓰고 `scenario-ideas.json`에
      30일 캐시(사람별·경로별). 프롬프트·시드·카테고리는 `gen-path-ideas.py`로 Swift에서 추출.
      경로로 만든 시나리오는 카테고리가 이미 정해져 categorize 호출을 건너뛴다. 에뮬레이터에서 확인: Cafe → ordering →
      모델이 쓴 여섯 개(Milk Alternative Mix-Up 등) → 탭하면 위 칸이 채워진다.
- [x] `FeedbackSheet` — 2026-09-13. 첫 통화 Done·첫 장면 완주 뒤 한 번, `beta_reviews`에 같은 행.
- [x] `VoiceComparisonSheet` — 2026-09-13. Me → "Doesn't sound like you?"(녹음 vs 클론, 같은 문장, 클론
      쪽은 fidelity 모델로 한 번 합성해 디스크 캐시) + "Re-record voice" 행과 확인 → 같은 클론 플로우로
      재녹음(`recloning`). 온보딩 Meet 단계 안의 비교 진입은 아직 없음.
- [ ] ~~`HistorySheet`~~ — iOS에서 아무 데도 안 쓰임(죽은 파일), N/A.
- [ ] ~~`LevelHeader`~~ — iOS에서 삭제됨, N/A.
- [x] `ReferralJoinSheet` — 2026-09-13. 포그라운드에서 `referral_redemptions`를 폴링, 첫 실행은
      조용히 기준점만, 새 합류는 무음 로컬 알림 + 시트. **미검증**: 다른 계정이 코드를
      써야 흐름이 보인다.
- [x] `LevelEqualizer` — 2026-09-13. 성장 탭에 네 기둥(어휘·유창성·문법·표현) × CEFR 여섯 칸.
      어휘는 실제로 쓴 단어를 등급으로 세어(15개 이상부터, 레벨이 높을수록 요구 개수가 늘어난다),
      나머지는 결정적 근사(말하기 속도·문법 점수·한 턴 길이)라 라벨에 ≈가 붙는다. 문법은 iOS의
      검증된 오류 밀도가 아직 안드로이드에 없어 0–100 점수 폴백 분기를 쓴다.

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
- [x] `DrillReminder` / `ItemReminder` / `TrialReminder` / `ReviewNotifications` — 2026-09-13.
      개별 항목 콜백은 이미 `ReviewQueue`에 있었고, 큐 전체를 부르는 알림(`DrillReminder`)을 붙였다:
      한 번에 하나만, 현재 큐에서 다시 계산, 09–21시로 당겨 맞추고, 이미 밀린 게 있으면 내일 아침.
      체험 종료 2일 전 알림(`TrialReminder`)은 무료 가격 단계가 있는 오퍼를 샀을 때 걸린다(문구는
      App Store가 아니라 Google Play). 알림이 꺼져 있으면 Me에 그 사실과 설정으로 가는 행이 뜬다.
- [x] `UILanguage` — 2026-09-13. 앱 화면이 학습자가 고른 자기 언어를 따른다(en·ko·ja·zh-Hant).
      Activity와 Application의 base context를 감싸서 적용 — 알림도 앱 컨텍스트에서 문자열을 읽는다.
      Me → 앱 언어 행 → 시트에서 고르면 액티비티를 새로 만든다. iOS 카탈로그의 ja·zh-Hant 열을
      `gen-strings.py --languages en,ko,ja,zh-Hant`로 가져오고(1347개), 안드로이드 전용 149개는
      새로 번역했다(ja는 기존 iOS ja 열의 용어를 따름, zh-Hant는 대만 중국어·간체 0자 검증).
      에뮬레이터에서 ko → ja → ko 전환 확인.
- [x] `AvatarStore` — 2026-09-13. 프로필 사진(정사각 크롭·512·JPEG), Talk 헤더가 "Me" 글자 대신
      얼굴을 달고, 프로필 편집 첫 단계에서 고른다. 사진이 없으면 이니셜, 그것도 없으면 사람 글리프.
- [x] ~~`VoiceSampleStore`~~ — 클론 녹음은 이미 `voice/clone-sample.wav`에 남고 비교 시트가 읽는다.
- [x] `MicChoiceSheet` / `MicPreference` — 2026-09-13. 헤드셋이 연결된 상태로 처음 마이크를 쓸 때
      한 번만 묻고(통화 화면), 그다음부터는 Me → 목소리에서 바꾼다. 기본은 끼고 있는 마이크
      (입 앞에 있다는 위치가 음질을 이긴다), 출력은 건드리지 않고 입력만 옮긴다
      (`setCommunicationDevice`, API 31+). **보이스 클론만 예외** — 방에서 제일 좋은 마이크로
      한 번 녹음해야 하므로 묻지 않고 내장 마이크를 쓴다. **실기기 검증 필요**: 에뮬레이터에
      블루투스 오디오 경로가 없다.
- [ ] ~~`UsageDetailView`~~ — iOS에서 2026-09-04에 `PlanPageView`로 접혔음, N/A.
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

### 화면 격차 (2026-09-13 감사 결과)

iOS 화면과 안드로이드 화면을 하나씩 비교해 나온 목록. 완료한 것만 여기 남기고,
남은 것은 아래 표에 이어서 적는다.

- [x] 통화 첫 몇 초가 빈 화면이던 것 — "대화를 시작하는 중…"(장면이면 "장면을 준비하는 중…")
- [x] 듣는 중 / 미래의 나가 생각하는 중 표시 — 조용한 화면은 멈춘 통화로 읽힌다
- [x] 통화 중 화면 꺼짐 방지 — 긴 침묵 턴에 폰이 잠기면 안 된다
- [x] 마이크 거부 안내 — 탭이 아무 일도 안 하고 이유도 없던 것, 설정으로 가는 길 포함
- [x] 첫 대화 전 안내 카드 — 링이 설명 없는 원으로 있던 것
- [x] 교정 칩 — 바뀐 단어만 강조(`SpokenWords`, 축약형 표는 Swift에서 추출)하고, 이유 밑에
      "내 언어로 설명"(translate 함수 + 디스크 캐시). 같이: 축약형만 바꾸는 제안은 버린다 —
      받아쓰기가 "I'm"을 "I am"으로 적으므로, 그걸 고치라는 건 하지 않은 실수를 지적하는 것.
      **미검증**: 제안은 실시간 턴에서만 붙고 에뮬레이터 마이크로는 사용자 턴이 나오지 않는다.
- [x] 하루 목표 편집 — Today 헤더의 슬라이더 버튼 → 네 가지 목표(0~50)와 알림 허용 여부.
      0은 그 항목을 하루에서 빼는 것. 번역문의 **굵게**가 별표로 보이던 것도 같이 고침.
- [x] 단어·표현 카드 — 라이브러리 행이 막다른 길이던 것. 뜻·예문·자주 쓰는 표현·내 대화에서 나온
      문장, 듣기·계속 학습·알아요·섀도잉·앞뒤 이동. 사전은 `WordLore`(공유 테이블)에서 오고,
      실패하면 다시 시도 버튼이 붙는다.
- [x] 라이브러리 입구 — 앱 안에서 들어갈 길이 아예 없었다(위젯 딥링크뿐). 단어·표현 타일의
      "전체"가 iOS처럼 사전을 연다.
- [x] 드릴 카드의 행동 — 뒤집은 면에 듣기·섀도잉·예문. 앞면에는 두지 않는다(답을 알려주게 된다).
- [x] 뉴스 섹션의 빈/로딩/재시도/실패 상태 — 관심사가 없으면 "관심사 추가", 받는 중이면 그렇다고,
      실패하면 "불러오지 못했어요"(이전 목록이 있으면 "지난 기사를 보여드려요"). 열 때 지난
      목록을 먼저 칠하고 뒤에서 새로 받는다 — 실패해도 섹션이 비지 않는다.
