-- ---------------------------------------------------------------------------
-- Every metering RPC becomes server-only.
--
-- All of them take `p_user_id` as an ARGUMENT, and all of them had kept
-- PostgreSQL's default PUBLIC execute grant, so anyone holding the app's anon
-- key — which ships inside the iOS binary and is public by design — could name
-- any account:
--
--   * `grant_credits(any_uuid, 999999999, ...)` minted balance out of nothing.
--     Verified reachable on production as `anon`, no login required: the call
--     passed the permission check and was refused only by the function's own
--     `p_credits >= 0` assertion. That is the hard paywall bypassed with one
--     HTTP request.
--   * the `charge_*` / `consume_metered_seconds` / `record_free_usage` family
--     let a caller burn a STRANGER's balance and daily cap. Victim uuids are
--     harvestable — `public_personas.owner_user_id` is readable by anon.
--
-- An `auth.uid() = p_user_id` guard cannot fix `grant_credits`: a caller
-- passing their OWN uuid is indistinguishable from a legitimate call. The only
-- fix that holds is removing client EXECUTE entirely, so the argument can no
-- longer be reached from outside the server.
--
-- The Edge Functions were changed to call these through `billingClient()` (the
-- service-role client) and deployed BEFORE this migration ran — every call
-- site already passed the id of the user it had just authenticated, so nothing
-- about the metering changes, only who is able to invoke it.
--
-- Not affected:
--   * nested calls — `consume_metered_seconds` from inside `charge_talk_seconds`,
--     `grant_credits` from inside `redeem_referral`. Both callers are SECURITY
--     DEFINER owned by postgres, so they execute as the owner.
--   * the RPCs the app really does call from the client: `redeem_referral`,
--     `core_my_progress`, `scene_allowance`. Those take no user argument (they
--     read `auth.uid()`) and keep their `authenticated` grant.
-- ---------------------------------------------------------------------------

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.grant_credits(uuid, integer, ledger_kind, text, text, text, jsonb)',
    'public.charge_credits(uuid, integer, text, text, text, jsonb)',
    'public.charge_talk_seconds(uuid, integer, text, text, jsonb)',
    'public.charge_tts_pooled(uuid, integer, text, text, text, jsonb)',
    'public.charge_tts_pooled(uuid, integer, text, text, text, jsonb, text)',
    'public.charge_tts_free_pooled(uuid, integer, text, text, text, jsonb, integer)',
    'public.charge_turn_tts_floored(uuid, integer, text, text, text, jsonb)',
    'public.consume_metered_seconds(uuid, integer, text, text, text, text, jsonb)',
    'public.record_free_usage(uuid, text, text, text, text, jsonb, integer)',
    -- Granted to `authenticated` an hour earlier in
    -- 20260814130000_begin_scene_play_grant to unbreak Watch; elevenlabs-tts
    -- now reaches it through the service-role client like the rest, so the
    -- grant is withdrawn again. Its auth.uid() guard stays as defence in depth.
    'public.begin_scene_play(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
