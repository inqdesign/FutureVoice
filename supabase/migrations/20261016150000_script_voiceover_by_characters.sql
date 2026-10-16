-- "Hear it in my voice" is priced by CHARACTERS, not audio length
-- (2026-10-16, founder: a one-minute script was quoted 3 minutes).
--
-- A talk minute carries ~300 characters of fluent-self speech (measured
-- 2026-09-26, 145-159 credits a call minute) and a voiceover is sold at 3x
-- that rate, so one talk minute per 100 characters:
--     charge_seconds = ceil(chars / 100) * 60      (1..60 min)
-- 3x the AUDIO length (20261014150000) charged a one-minute English script
-- (~800 characters) 3 minutes, which is about one talk minute's worth of
-- voice. The app's `ScriptVoiceover.chargeMinutes(characters:)` is the same
-- formula; keep the two the same.
--
-- The cap stays: the charge is least(price(chars), quoted_seconds), so a
-- build that still quotes 3x the audio pays exactly what its button showed,
-- never more. The characters are the reservation's `max_chars` (what the app
-- reported; lines can't synthesize past twice that). The quote floor is left
-- as it was, so an older build's honest quote is never raised.
--
-- Replaces one function (script_voiceover_settle) and adds one.

create or replace function public.script_voiceover_char_price(p_chars integer)
 returns integer
 language sql
 immutable
as $$
  select (least(60, greatest(1, ceil(greatest(p_chars, 0) / 100.0))) * 60)::integer;
$$;

-- Charges one reservation (internal). Returns the jsonb the app reads.
create or replace function public.script_voiceover_settle(p_user_id uuid, p_key text,
                                                          p_audio_seconds numeric)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $$
declare
  v_row    script_voiceovers%rowtype;
  v_audio  numeric;
  v_charge integer;
  v_wall   text;
  v_result jsonb;
begin
  select * into v_row from script_voiceovers
   where user_id = p_user_id and key = p_key
   for update;
  if not found then
    return jsonb_build_object('error', 'not_reserved');
  end if;
  if v_row.status = 'charged' then
    return jsonb_build_object('status', 'charged', 'charged_seconds', v_row.charged_seconds,
                              'already', true);
  end if;

  v_audio := greatest(coalesce(p_audio_seconds, 0), v_row.server_audio_seconds);
  v_charge := least(public.script_voiceover_char_price(v_row.max_chars), v_row.quoted_seconds);
  v_charge := greatest(v_charge, 60);

  v_wall := public.script_voiceover_wall(p_user_id, v_charge);
  if v_wall is not null then
    return jsonb_build_object('error', v_wall);
  end if;

  begin
    v_result := public.consume_metered_seconds(
      p_user_id         => p_user_id,
      p_seconds         => v_charge,
      p_pool            => 'talk_seconds',
      p_action          => 'script_voiceover',
      p_source_fn       => 'script-voiceover',
      p_idempotency_key => 'script_voiceover:' || p_user_id::text || ':' || p_key,
      p_metadata        => jsonb_build_object('voiceover_key', p_key,
                                              'audio_seconds', round(v_audio, 1),
                                              'chars', v_row.max_chars,
                                              'quoted_seconds', v_row.quoted_seconds));
  exception
    when others then
      if sqlerrm like '%DAILY_CAP_REACHED%' then return jsonb_build_object('error', 'daily_cap_reached'); end if;
      if sqlerrm like '%FAIR_USE_LIMIT%' then return jsonb_build_object('error', 'fair_use_limit'); end if;
      if sqlerrm like '%INSUFFICIENT_CREDITS%' or sqlerrm like '%NO_CREDIT_ROW%' then
        return jsonb_build_object('error', 'insufficient_credits');
      end if;
      raise;
  end;

  update script_voiceovers
     set status = 'charged', charged_seconds = v_charge, settled_at = now()
   where user_id = p_user_id and key = p_key;

  return jsonb_build_object('status', 'charged', 'charged_seconds', v_charge,
                            'balance', v_result->'balance');
end;
$$;

revoke all on function public.script_voiceover_char_price(integer) from public, anon, authenticated;
revoke all on function public.script_voiceover_settle(uuid, text, numeric) from public, anon, authenticated;
