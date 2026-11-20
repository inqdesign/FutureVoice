# Brief · Speech Season 2 (1.3.2 release carousel)

## One message (fixed — do not reopen)

영어 스피치 챌린지가 시즌 2로 넘어가요. 같은 원고를 읽은 **원어민의 낭독과 비교해서** 점수가
나와요 — 속도 · 리듬 · 쉼 · 정확도 · 발음 다섯 가지로 쪼개서. 점수에는 별명이 붙고, 결과
화면이 새로워요: 점수가 **내가 찍은 영상 위에** 뜨고, 자세한 건 아래에서 끌어올리는 시트에 있어요.

EN gloss (for the designer, not copy): English speech challenges move to Season 2 — your reading
is scored against a native reading of the SAME script, broken into speed · rhythm · pauses ·
accuracy · pronunciation, your score earns a nickname, and the new result page puts the score over
your own video with the details on a pull-up sheet.

## Who it's for / when it lands

직장인·학생 중 **소리 내어 읽는 연습을 이미 하고 있는 사람** — 발음과 낭독이 "대충 통하긴
하는데 얼마나 괜찮은 건지" 모르겠는 사람. 하한선은 지키기 (BRAND 정직한 바닥): 더듬더듬
문장을 만드는 수준 이상, 완전 초보 아님. 낭독은 그 위 레벨의 연습이라 자연스럽게 걸러짐.

지금 내보내는 이유: 1.3.2 (138) 릴리스 헤드라인. English first — 영어 챌린지부터 열렸고,
다른 언어·안드로이드는 나중이라 카피에서 "영어 챌린지"로 정직하게 한정할 것.

## The hook (cover line, positive-first)

점수가 아니라 **원어민과 나란히 놓고** 본다 — 한 숫자가 아니라 다섯 가지로.
→ cover 카피는 "원어민이 읽은 같은 원고와 겨뤄요" 쪽으로. "발음 완벽하게" 같은 과장 금지;
핵심은 "진짜 원어민 낭독을 기준 삼아, 좋은 낭독을 이루는 것들로 쪼개서 보여준다"는 정직함.

## Proof in the app (all renderable from `web/kit/screens/speech.js`)

- **The new result page** = the `take-page` take page (`SpeechResultView.page`): 점수(88)가 영상
  위에 크게 뜨고, 그 아래 `.tv` 한 줄 + `.tlv` **별명**("외국계 회사 에이스 레벨" / "Star of the
  global office level"), 맨 아래 유리 시트(`.tsheet`)에 Season 2 점수 스트립 `.tscores`.
  → `<nw-speech take-page>` (camera-photo 없으면 앱 기본 그라데이션 스탠드인; 실제 인물 사진 금지).
- **The Season 2 score strip** (`SpeechResultView.scoreStrip`, 코드 `_buildTake`/`.tscores`):
  다섯 칸 — Speaking speed · Rhythm · Pauses · Accuracy · Pronunciation — 숫자 + 바
  (샘플 76·79·92·97·97, ≥85 녹색 / 그 아래 주황). 이게 "원어민 낭독 대비"의 시각적 증거.
- **The prompter** (`SpeechPrompterView`): 원고를 프롬프터로 읽는 화면 (camera on) — 입력쪽.
  → `prompter` / `camera` pose.
- **The board moment sheet** (`SpeechChallengeMomentSheet`): 챌린지 보드 순위 — `rank-up` pose.
  영어 챌린지엔 보드가 있다는 사실은 참이지만, 이번 메시지의 주인공은 아님(보조로만).

숫자는 전부 kit 샘플 데이터 — 유저 통계로 제시 금지 (BRAND).

## Outline — 6 cards (cover → 4 → outro)

세 번 등장하는 take page는 각각 **다른 beat**(전체 공개 → 다섯 지표 → 별명)로 프레이밍하고,
모션·스티커·강조 위치를 바꿔 반복이 아니라 전개로 읽히게 할 것. 제목은 픽셀, ~10 Hangul/줄.

1. **Cover** — 메시지: "스피치 챌린지, 시즌 2 / 원어민이 읽은 같은 원고와 겨뤄요."
   화면: take page 히어로 — 영상 위 점수(88) + 별명 한 줄, 시트 살짝 보이게.
   pose `take` (`take-page`, camera-photo 스탠드인). 모션: 폰이 커지며 들어오고 텍스트 페이드.

2. **같은 원고, 원어민도 읽어요** — 네 낭독을 **원어민 낭독과 나란히** 놓고 점수를 매긴다는 개념.
   화면: 프롬프터로 원고 읽는 화면(camera on). pose `prompter`.
   스티커 도움: 작게 "원어민 / 나" 두 줄 대비 태그(kit 요소 범위 내) — 있으면 좋고 없어도 됨.

3. **한 숫자가 아니라 다섯** — 속도 · 리듬 · 쉼 · 정확도 · 발음. 좋은 낭독을 이루는 것들로 쪼갠다.
   화면: take page, 아래 시트 **끌어올린** 상태로 `.tscores` 다섯 칸이 주인공.
   pose `take`, 강조는 `.tscores`. 이 카드가 메시지의 심장 — 가장 공들일 것.

4. **점수엔 별명이 붙어요** — 숫자 위에 얹히는 한 줄 칭호("외국계 회사 에이스 레벨").
   화면: take page, `.tlv` 별명 줄을 포커스/확대. 스티커: 별명 줄을 작은 pill로 띄우기.
   pose `take`, 별명 강조. ("Never grade the reader"는 요금제 등급 얘기 — 낭독 점수의 별명은
   성취 톤이라 OK, 다만 사람을 등급 매기는 문구로 쓰지 말 것.)

5. **결과 화면이 새로워요** — 점수가 **내가 찍은 영상 위에** 뜨고, 자세한 건 아래에서 끌어올려 봐요.
   화면: take page 전체 — 히어로(영상+점수) ↔ 시트 올라오는 인터랙션. pose `take`.
   모션: 시트가 아래에서 슬라이드업(새 화면의 작동 방식 그 자체).
   (선택: 보드까지 넣고 싶으면 이 자리에 `rank-up`을 끼워 "베스트 테이크가 영어 보드에 올라가요"로
   돌릴 수 있음 — 단 take page 한 번 줄이면 4·5 사이 별명/새 화면을 한 카드로 합쳐야 함.
   autopilot 기본안은 위의 take page 유지.)

6. **Outro** — 템플릿 그대로: 워드마크 · "유창한 나에게 언어를 배우세요." · "첫 20분은 무료예요" ·
   nawana.app.

## Channels

- **IG carousel** (기본, 1080×1350): cover PNG, 2–5 비디오(take page 시트 슬라이드업·프롬프터
  스크롤·숫자 카운트업), outro PNG. 캡션 첫 줄 = 훅("원어민이 읽은 같은 원고와 겨뤄요").
  해시태그 3–5 (#영어회화 #영어발음 #스피킹 #영어낭독).
- **Threads**: 앞 5장 재활용 + 짧은 대화체 텍스트("영어 스피치 챌린지 시즌 2 — 원어민 낭독이랑
  겨뤄서 속도·리듬·쉼·정확도·발음 다섯 개로 점수가 나와요").
- **Community feature series** ("나와나로 할 수 있는 것"): Speech는 아직 시리즈에 없음 — 이 캐러셀을
  미러해 Speech 항목으로 추가(다음 빈 id, cat `practice`). publisher가 처리, 배포는 대표 승인.

## Risks / claims to check

- **English only**: "영어 챌린지"로 한정. 다른 언어·안드로이드가 다 된다고 말하지 말 것.
- **별명**: 샘플 텍스트는 kit 것 그대로 쓰고, 실제 유저 별명·통계로 제시 금지.
- **"원어민과 비교"**: "발음을 완벽하게/네이티브처럼"으로 넘기지 말 것. 핵심은 "실제 원어민 낭독을
  기준으로, 좋은 낭독을 이루는 요소로 쪼개서 보여준다" — 측정이지 완성 약속이 아님.
- **숫자**: 슬라이드의 점수/바는 kit 샘플. 유저 결과로 오해되지 않게.
- **보드**: 영어 챌린지엔 보드가 있음(참), 단 이번 메시지 주인공 아님. 시즌 1은 계속 연습 가능하고
  시즌이 닫혀도 사라지지 않음 — 카피에서 손실("없어져요")로 쓰지 말 것.
- 인물 사진 금지(camera-photo 미지정 → 앱 기본 그라데이션 스탠드인).

## Success signal

스피치 탭 진입(speech tab opens)·챌린지 응시 수, 캐러셀 saves·프로필 방문, 커뮤니티 Speech
항목 조회. 발음/낭독에 관심 있는 세그먼트가 저장을 더 하는지(연습형 콘텐츠의 저장률)가 기준.
