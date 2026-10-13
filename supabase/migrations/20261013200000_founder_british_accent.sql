-- The founder's voice speaks British English (2026-10-13). Same Cartesia
-- voice (af2852ce…, remade from a cleaned take the same day), the accent in
-- the id. The app adopts it on its next launch.
do $$
declare
  v_user uuid := '72bcaa7e-3dd2-4364-b197-078ba59c1ce4';
  v_from text := 'af2852ce-6743-4730-8623-6d21a3d60d37:general-american';
  v_to text := 'af2852ce-6743-4730-8623-6d21a3d60d37:british';
begin
  if not exists (select 1 from voice_clones
                 where user_id = v_user and elevenlabs_voice_id = v_from and is_active) then
    return;
  end if;
  update voice_clones set is_active = false where user_id = v_user and is_active;
  insert into voice_clones (user_id, elevenlabs_voice_id, is_active, name)
  values (v_user, v_to, true, 'Future Eunggyu');
end $$;
