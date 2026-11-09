-- Takes the test challenge out of draft Season 2 (founder, 2026-11-09), so it
-- is not on the list when the season opens. Deleted rather than retired: a
-- retired challenge still shows as Past. Its two test entries go with it (the
-- foreign keys cascade). The title in the condition keeps this to that row.
delete from public.speech_challenges
where id = 'a12f7206-cadc-418e-b139-cab37ff3e492'
  and title = '[Test] Why practise out loud?'
  and season = 2;
