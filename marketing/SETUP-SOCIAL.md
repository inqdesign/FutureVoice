# 인스타그램·스레드 자동 게시 설정 (대표님이 한 번 하는 일)

자동 게시와 조회수 분석은 Meta의 공식 API로 해요. 계정 로그인 정보는 저장하지 않고,
대표님이 발급한 **접근 토큰**만 이 맥의 `~/.config/nawana/marketing.env`에 둬요(저장소에는
절대 들어가지 않아요). 토큰이 없으면 팀은 커뮤니티 페이지에만 올리고, 인스타·스레드는
건너뛰었다고 어드민에 기록해요.

Meta 화면의 메뉴 이름은 자주 바뀌어요. 아래와 다르게 보이면 비슷한 이름을 찾거나 화면을
캡처해서 보여주세요.

## 1. 인스타그램을 프로페셔널 계정으로 (5분, 무료)

1. 인스타그램 앱 → 프로필 → ☰ → **계정 유형 및 도구** → **프로페셔널 계정으로 전환**
2. **비즈니스**를 고르세요(크리에이터도 되지만, 비즈니스가 인사이트를 더 줘요).
   카테고리는 "교육" 또는 "앱 페이지".
3. 페이스북 페이지 연결은 건너뛰어도 돼요. 우리가 쓰는 "Instagram 로그인 API"는 페이지가
   필요 없어요.

## 2. Meta 개발자 앱 만들기 (10분)

1. https://developers.facebook.com → 로그인 → **내 앱** → **앱 만들기**
2. 사용 사례에서 **Instagram API** ("Instagram에서 메시지 및 콘텐츠 관리")를 고르세요.
   같은 앱에 **Threads API 액세스** 사용 사례도 추가하세요.
3. 앱 이름은 `nawana marketing` 정도로. 비즈니스 포트폴리오는 없으면 건너뛰세요.
4. 앱은 **개발 모드**로 둬도 돼요. 내 계정에만 올리는 용도라 앱 검수가 필요 없어요.

## 3. 인스타그램 토큰

1. 앱 대시보드 → **Instagram API** → **API 설정(Instagram 로그인)**
2. **역할 → Instagram 테스터**에 우리 인스타 계정을 추가 → 인스타그램 앱(또는 웹)
   설정 → **앱 및 웹사이트 → 테스터 초대**에서 수락
3. 다시 대시보드에서 **액세스 토큰 생성** → 우리 계정으로 로그인·허용.
   권한: `instagram_business_basic`, `instagram_business_content_publish`,
   `instagram_business_manage_insights`
4. 나온 **토큰**과 **Instagram 사용자 ID**(숫자)를 복사하세요. 대시보드 토큰은 60일짜리
   장기 토큰이에요. 이후 갱신은 팀의 스케줄러가 매주 자동으로 해요.

## 4. 스레드 토큰

1. 같은 앱 → **Threads API 액세스** → **역할 → Threads 테스터**에 같은 계정 추가 →
   스레드 앱 설정 → **계정 → 웹사이트 권한 → 초대**에서 수락
2. **Threads API → 사용자 토큰 생성기**에서 토큰 생성.
   권한: `threads_basic`, `threads_content_publish`, `threads_manage_insights`
3. 토큰과 **Threads 사용자 ID**를 복사하세요.

## 5. 이 맥에 넣기

    mkdir -p ~/.config/nawana && chmod 700 ~/.config/nawana
    cat > ~/.config/nawana/marketing.env <<'ENV'
    IG_USER_ID=여기에_인스타_사용자_ID
    IG_ACCESS_TOKEN=여기에_인스타_토큰
    THREADS_USER_ID=여기에_스레드_사용자_ID
    THREADS_ACCESS_TOKEN=여기에_스레드_토큰
    VETO_HOURS=12
    ENV
    chmod 600 ~/.config/nawana/marketing.env

토큰은 채팅에 붙여넣지 마세요. 파일에만 넣으면 돼요.

## 6. 확인

    python3 scripts/marketing/scheduler.py --dry-run

"instagram: configured", "threads: configured"가 보이면 끝이에요.
