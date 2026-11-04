-- Michelle Yeoh's challenge pointed at a clip that is private on YouTube
-- ("This video is private", founder 2026-11-04). ABC7's upload of the
-- full speech instead; ABC broadcast the Oscars.
update public.speech_challenges
   set link = 'https://www.youtube.com/watch?v=8v9wrK_j6Cc'
 where id = '5beec000-0000-4000-8000-000000000024';
