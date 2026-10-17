-- Android 1.1.11 (15) is on the closed-test track (2026-10-18): build 14's
-- changes plus Say it again's "Read both sides".
update public.app_release set
  latest_build = 15,
  latest_beta_build = 15,
  latest_version = '1.1.11',
  notes_ko = E'• 처음 시작할 때 내 루틴을 만들어요. 매일 전화 받을 시간과 하루 공부 시간을 정하면 한 주 계획표에 바로 들어가요.\n• 사람 추가가 한 화면으로 끝나고, 상대를 고르다가 바로 새 사람을 만들 수 있어요.\n• 스피치 챌린지를 카드로 넘겨 보고, 복습 화면에서 주간 테스트를 바로 볼 수 있어요.\n• 다시 말하기에서 미래의 나 대사까지 직접 말해 볼 수 있어요. 왼쪽 위 버튼에서 ''양쪽 대사 모두 읽기''를 켜요.\n• 휴대폰을 다시 켜도 매일 오는 전화가 그대로 울려요.\n• 뉴스 통화의 제목이 잘려 보이던 것을 고쳤어요.\n• ''내 목소리로 듣기''가 원고 길이보다 시간을 많이 쓰던 것을 고쳤어요.',
  notes_en = E'• Set up your routine when you start: pick when your daily call rings and how long you study, and it lands on your weekly plan.\n• Adding a person takes one screen, and you can create someone new from the person picker.\n• Swipe through speech challenges as cards, and find the weekly test on the Review screen.\n• In Say it again, you can now say your fluent self''s lines too. Turn on Read both sides from the button at the top left.\n• Your daily call still rings after the phone restarts.\n• News call titles are no longer cut off.\n• Hear it in my voice no longer costs more time than the script.',
  updated_at = now()
where platform = 'android';
