-- Olivia (1f5c04ca) speaks in the Cartesia voice the founder made from her
-- recording on 2026-10-12 ("Olivia", cd2ca05a-…), the S takes of the A/B mail.
-- Same swap voice-move makes: the active row goes inactive, the new voice is
-- inserted active. The app adopts it on its next launch
-- (restoreVoiceCloneFromCloud). The old ElevenLabs voice is left upstream.
do $$
declare
  v_user uuid := '1f5c04ca-e7e9-4b82-a962-99988b341ed1';
  v_voice text := 'cd2ca05a-92c8-4fda-9973-1755ead6661d';
begin
  if exists (select 1 from voice_clones
             where user_id = v_user and elevenlabs_voice_id = v_voice and is_active) then
    return;  -- already applied
  end if;
  update voice_clones set is_active = false where user_id = v_user and is_active;
  insert into voice_clones (user_id, elevenlabs_voice_id, is_active, name)
  values (v_user, v_voice, true, 'Future olivia');
end $$;
