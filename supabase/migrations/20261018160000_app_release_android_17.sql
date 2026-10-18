-- Android 1.1.11 (17) is on the closed-test track (2026-10-18): build 16 plus
-- the call-mode echo fix and the layout / shadowing / Talk-tab fixes.
update public.app_release set
  latest_build = 17,
  latest_beta_build = 17,
  latest_version = '1.1.11',
  notes_ko = E'• 처음 시작할 때 내 루틴을 만들어요. 매일 전화 받을 시간과 하루 공부 시간을 정하면 한 주 계획표에 바로 들어가요.\n• 사람 추가가 한 화면으로 끝나고, 상대를 고르다가 바로 새 사람을 만들 수 있어요.\n• 스피치 챌린지를 카드로 넘겨 보고, 복습 화면에서 주간 테스트를 바로 볼 수 있어요.\n• 다시 말하기에서 미래의 나 대사까지 직접 말해 볼 수 있어요. 왼쪽 위 버튼에서 ''양쪽 대사 모두 읽기''를 켜요.\n• 통화 중에 미래의 나 목소리가 내 말에 섞여 들어가지 않아요.\n• 앱을 열 때 Talk 탭의 인사말과 원이 덜컹 올라가지 않아요.\n• 섀도잉에서 다음 문장에 이전 피드백이 남지 않고, 마지막 문장 피드백도 끝까지 보여요.\n• 글자를 크게 키운 폰에서도 탭 바와 버튼이 겹치지 않아요.\n• 휴대폰을 다시 켜도 매일 오는 전화가 그대로 울려요.\n• 일본어나 스페인어를 배울 때 사람 목록이 비어 보이던 것을 고쳤어요.',
  notes_en = E'• Set up your routine when you start: pick when your daily call rings and how long you study, and it lands on your weekly plan.\n• Adding a person takes one screen, and you can create someone new from the person picker.\n• Swipe through speech challenges as cards, and find the weekly test on the Review screen.\n• In Say it again, you can now say your fluent self''s lines too. Turn on Read both sides from the button at the top left.\n• Your future self''s voice no longer leaks into what you say during a call.\n• The Talk tab''s greeting and ring no longer jump when the app opens.\n• In shadowing, the last line''s feedback no longer carries over, and the final line''s feedback shows in full.\n• The tab bar and buttons no longer overlap on phones with large text.\n• Your daily call still rings after the phone restarts.\n• When learning Japanese or Spanish, the people list is no longer empty.',
  updated_at = now()
where platform = 'android';
