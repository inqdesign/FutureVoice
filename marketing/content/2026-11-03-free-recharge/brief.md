# Brief — 무료 20분, 그리고 리포트 끝의 한 번 더 (2026-11-03-free-recharge)

- stage: brief → copy
- piece: IG carousel (6 cards) + Threads + community mirror
- source of truth: CLAUDE.md "The free minutes end in a REPORT, not a paywall",
  commit 37d6cc3f, fastlane/metadata/ko/release_notes.txt, status.md (facts fixed there)

## One message

**무료 20분을 다 쓰면, 리포트 끝에서 한 번 더 20분을 무료로 충전할 수 있어요.**

Framed as acquisition, not as a billing announcement: 나와나는 깔자마자 말하게 하고
(첫 20분 무료, 결제 요구 없음), 그 20분이 끝나면 빈 페이월이 아니라 **내 말로 만든
리포트**가 나오고, 그 리포트 끝에 20분이 한 번 더 있다. "일단 실컷 말해보고 판단해도
된다"가 피스 전체의 약속.

## Who it's for

1차 (acquisition): 영어 회화 앱을 깔까 말까 망설이는 직장인 — 말하기 연습이 필요한 걸
알지만, 열자마자 구독부터 들이미는 앱에 데인 사람. 더듬더듬이라도 문장은 만드는 수준
(honest floor — 완전 초보 약속 금지).

2차 (re-engagement): 무료 20분을 다 쓰고 멈춘 설치자. 이 사람에겐 "앱을 업데이트하고
열면 리포트가 기다리고, 그 끝에 20분이 한 번 더 있다"가 뉴스다 (RootTabView가
launch/foreground에서 리포트를 올리므로 사실).

## Why now

- 1.2.9 (129)가 이 기능을 싣고 나감 — 기능이 생긴 날이 말할 날.
- 측정된 문제에 대한 답이기도 함: 무료 분을 쓴 뒤 첫날 이후 이탈이 패턴이었고
  (free-minutes conversion analysis), 이 기능이 정확히 그 지점을 겨냥한다. 이 포스트는
  그 이탈자들이 보는 피드에 닿는 두 번째 기회.

## Proof in the app (real behaviour only)

- 첫 20분 무료, 가입 즉시, 스토어 체험 없음 (BRAND.md 가격 사실; "체험"이라는 단어 금지).
- 20분이 끝나면 통화가 스스로 마무리되고 리포트가 나온다: 앱을 어떻게 썼는지, **내가
  말한 시간에서 읽은 레벨**, 응시 가능한 시험(강요 아님, 건너뛰기 가능), 이어갈 루틴.
- 1.2.9부터 리포트 마지막 카드가 "구독하기 | 20분 무료 충전" — 충전은 **계정당 한 번**,
  구독한 적 없는 계정만, 무료 분을 다 쓴 뒤에만.
- 기트 화면 대응: `nw-call`(무료 분이 사주는 것), `nw-home`(Talk 탭 — 링·뉴스·상황),
  `nw-weekreport`(리포트 덱의 생김새 — 트라이얼 리포트는 같은 덱의 트라이얼 모드),
  `nw-review`(말한 통화가 교재로 남아 있음).

## Outline (6 cards)

**HARD CONSTRAINT (status.md): 충전 오퍼에는 캡처도 키트 화면도 없다. 오퍼는 한 카드의
TEXT로만 말하고, 버튼·리포트 마지막 카드를 그리거나 흉내 내지 않는다. 모든 카드의
비주얼은 기존 키트 화면 또는 표준 커버/아웃트로만.**

1. **Cover** — "첫 20분은 무료예요. 내 목소리의 유창한 나와 통화." 긍정 먼저, 가격 얘기
   없이 얻는 것부터. Visual: `nw-phone` + `nw-call` (정지 이미지로도 성립해야 함).
2. **20분 동안 뭐든** — 자유 대화, 오늘 뉴스, 내가 앞둔 상황. 탭 한 번에 전화가 걸린다.
   Visual: `nw-home` (링 → 스크롤로 뉴스·상황 목록).
3. **말하는 동안 교정이 따라와요** — 틀린 문장은 그 자리에서 고쳐지고, 전부 내 교재가
   된다 (differentiator: 모든 대화가 내 학습 자료). Visual: `nw-call` fix 카드 장면.
4. **다 쓰면 리포트가 나와요** — 어떻게 썼는지, 내가 말한 시간에서 읽은 레벨, 볼 수 있는
   시험, 이어갈 루틴. 페이월이 아니라 리포트라는 게 포인트. Visual: `nw-weekreport`
   (덱 카드 느낌만 — "이번 주" 프레이밍 문구가 보이면 디자이너가 그 장면은 피할 것).
5. **리포트 끝에 한 번 더** — ★오퍼 카드, 텍스트로만★: "리포트 끝에서 20분을 한 번 더
   무료로 충전할 수 있어요 (계정당 한 번)." + 멈췄던 사람용 한 줄: "예전에 20분을 다
   썼다면, 업데이트하고 열어보세요 — 리포트가 기다려요." Visual: `nw-home`의 링(다시
   걸 수 있는 전화 = 충전이 사주는 것). 오퍼 UI는 절대 그리지 않는다.
6. **Outro** — 표준: wordmark · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요"
   · nawana.app. (아웃트로의 고정 문구가 메시지를 한 번 더 받친다.)

Stickers: 카드 3에 교정 카드 스티커 허용. 비교 컷 불필요.

## Channels

- Instagram carousel (6 × 1080×1350) — 기본. 캡션 첫 줄이 훅: 무료 20분 + 리포트 끝의
  한 번 더. 해시태그 3–5개 ko+en.
- Threads — 카드 1–5 재사용, 짧은 구어체 텍스트 (IG 캡션 복붙 금지).
- Community mirror — series 엔트리 (cat `start`, e01 "나와나 한눈에" 계열의 확장이지
  반복 아님: e01은 앱 전체, 이 피스는 "공짜로 시작하는 길"). 릴리스 뉴스는 beta.sh가
  따로 올리므로 중복 뉴스 금지.
- Korean primary (해요체, "당신" 금지), English secondary.

## Risks / copy traps

- **"체험" 금지.** 스토어 체험은 삭제됐다 (11-03). "무료 체험", "trial"이라는 단어가
  한 번이라도 들어가면 FIX. "무료 20분" / "무료 충전"으로만.
- **"한 번 더"는 반드시 "계정당 한 번"과 함께.** 무한 충전으로 읽히면 거짓 약속.
- **스위치 확인:** 충전 크기는 `billing_config.free_recharge_seconds` (billing-switch.py,
  0이면 버튼이 안 그려짐). 게시 전 리뷰어가 값이 1200(20분)으로 살아 있는지 확인할 것.
- **구버전 빌드는 버튼이 없다.** 2차 타깃(멈춘 설치자)용 문구는 "업데이트하고 열면"을
  포함할 것 — 1.2.9 미만은 리포트만 보고 충전은 못 본다.
- **리포트 숫자는 샘플.** `nw-weekreport`의 수치를 사용자 통계처럼 쓰지 말 것.
- zero-to-fluent 금지, 완전 초보 타깃팅 금지 (honest floor).
- 레벨 카드 문구는 "내가 말한 시간에서 읽은 레벨" 수준까지만 — "정확한 CEFR 진단" 같은
  과장 금지 (앱 스스로 thin-speech면 "첫 읽기"라고 말한다).

## Success signal

- IG saves + profile visits, Threads views; community series 조회수 (admin 마케팅 탭).
- PostHog (읽기 전용): 게시 후 1주 `trial_report` 열림, `claim_free_recharge` 사용
  (ledger key `free_recharge:<uid>`), 미구독 계정의 재방문 — 포스트가 2차 타깃에
  닿았는지의 가장 정직한 신호.
