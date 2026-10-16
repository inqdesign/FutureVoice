-- Android 1.1.10 (13) is on the closed-test track (2026-10-16): testers on 12
-- are told on their first screen, with what changed. Same words as the Play
-- release notes (android/fastlane/.../changelogs/13.txt), in the sheet's
-- bullet form.
update public.app_release set
  latest_build = 13,
  latest_beta_build = 13,
  latest_version = '1.1.10',
  notes_ko = E'• 스페인어를 배울 수 있어요. 멕시코식과 스페인식 억양 중에 고를 수 있어요.\n• 일본어 단어를 더 정확하게 나눠요.\n• A2 레벨에서도 ''보내기로 답하기''가 기본으로 켜져요.\n• 통화 중에 화면이 깜빡이거나 대화가 위아래로 흔들리지 않아요.\n• 탭 안내 카드가 위아래로 움직이지 않아요.\n• 설정 화면 글자가 한결 편하게 읽혀요.',
  notes_en = E'• Learn Spanish, with a Mexican or a Castilian accent.\n• Japanese words are split more accurately.\n• At A2, "Answer with Send" is now on by default.\n• The call screen no longer flickers or jumps while you talk.\n• Tab guide cards no longer bounce up and down.\n• Settings text is easier on the eye.',
  updated_at = now()
where platform = 'android';
