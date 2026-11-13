-- English Season 2 starts its boards fresh (2026-11-13, founder: "the
-- earlier attempts don't matter much, re-judge them if we can").
--
-- Takes are now judged against ONE reference, the listening reading the
-- learner hears, instead of the male/female pair; the area scores on file
-- were measured against the pair, and the server keeps only those, so it
-- cannot re-judge them. Each phone re-judges its own takes when their result
-- is opened (SpeechReadingRejudge) and a camera take goes back on the board
-- under the new rule. This clears the English Season 2 entries so no
-- old-rule score sits above them. Season 1 and other languages are untouched.

delete from speech_challenge_entries e
using speech_challenges c
where c.id = e.challenge_id
  and c.language = 'en'
  and c.season = 2;
