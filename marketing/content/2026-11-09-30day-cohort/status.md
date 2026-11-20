# 30일 기수 프로모션 캐러셀

- **Stage:** brief (brief.md written, waiting for the founder on outline, poster ground, A/B)
- **Owner:** team lead
- **Request (founder, 2026-11-09):** "캠페인 캐로셀도 만들어줘봐. 프로모션 포스터를 처음에 만들고 캐로셀 커버보단 뭔가 더 임팩트가 있도록"
- **Campaign (founder approved the concept, 2026-11-09):** 새 구독자를 늘리기 위한 기간 한정 이벤트. 7일 모집, 30일 기수, 30일 중 20일 말하면 한 달 무료.

## Open questions for the founder

1. 보상 시점: 첫 갱신이 기수 진행 중에 오기 때문에 "둘째 달 무료"는 지급이 안 맞음. 30일을 유지하면 "완주 뒤 다음 결제 1회 무료"(대부분 셋째 달), 둘째 달을 지키려면 21일 기수.
2. 모집 기간과 기수 시작일 날짜.
3. 하루 기준(잠정: 4분, Core와 같은 240초)과 20일이 적절한지. 실사용 데이터 확인 전.
4. 인원 한정 여부.

## Not verified yet

- 기존 구독자가 Apple 무료 코드를 쓰면 언제부터 적용되는지(공식 문서에 명시 없음, 샌드박스 확인 필요).
- 무료 코드가 `FREE_TRIAL`로 오면 서버가 `trialing`으로 처리해 그 달 통화 풀이 7/30로 줄어듦. 이벤트 전에 수정 필요.
- Android에서 같은 보상을 주는 방법.
