-- One learner's existing clone speaks German through a Hochdeutsch remix
-- (2026-10-08, founder's call after an A/B by ear). New clones get this on
-- their own (`applyDefaultAccent` / `_shared/default-accent.ts`); a clone made
-- before that is switched by hand, here.
--
-- The remix m9rgDteJxLXdvkhPyFck was made from Fn62Aevg8PdySO7VRCCK with the
-- catalog's prompt at prompt_strength 0.3, first take. It is mirrored as an
-- INACTIVE row so account deletion, the anonymous sweep and parking delete it
-- with the source; the app keeps the source id and the TTS function and the
-- gateway speak through the remix for German lines.

insert into public.voice_clones (user_id, elevenlabs_voice_id, is_active, name)
select user_id, 'm9rgDteJxLXdvkhPyFck', false, name
from public.voice_clones
where elevenlabs_voice_id = 'Fn62Aevg8PdySO7VRCCK'
  and not exists (select 1 from public.voice_clones where elevenlabs_voice_id = 'm9rgDteJxLXdvkhPyFck');

update public.voice_clones
set accent_by_server = true,
    speak_as_voice_id = 'm9rgDteJxLXdvkhPyFck',
    speak_as_language = 'de',
    speak_as_accent = 'de-DE',
    speak_as_started_at = null
where elevenlabs_voice_id = 'Fn62Aevg8PdySO7VRCCK';
