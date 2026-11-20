// Helpers shared by every Edge Function in this project.
// Imported by sibling functions via: `import { requireUser, cors } from "../_shared/auth.ts"`
//
// Note: Supabase Edge Runtime auto-verifies the JWT before invoking the
// function (see `verify_jwt = true` default in config.toml), so by the time
// we run here the Authorization header is guaranteed to be a valid signed
// Supabase JWT. We still call `auth.getUser()` to extract the user id —
// useful for logging, rate-limiting hooks, and tying voice ids
// to a specific user when we record usage.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0"

export interface AuthedRequest {
  user: { id: string; email?: string; isAnonymous: boolean }
  supabase: SupabaseClient
}

/** An anonymous session exists only to clone and hear the voice before the
 *  sign-up step, so it is refused everywhere except the functions that pass
 *  `allowAnonymous` (the voice ones the onboarding calls). On 2026-11-20 a
 *  script minted anonymous users with the public anon key by the dozen. */
export async function requireUser(
  req: Request,
  opts: { allowAnonymous?: boolean } = {},
): Promise<AuthedRequest | Response> {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "missing Authorization" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...cors() },
    })
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data, error } = await supabase.auth.getUser()
  if (error || !data.user) {
    return new Response(JSON.stringify({ error: "invalid session" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...cors() },
    })
  }
  const isAnonymous = data.user.is_anonymous === true
  if (isAnonymous && !opts.allowAnonymous) {
    return new Response(JSON.stringify({ error: "account required" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...cors() },
    })
  }
  return { user: { id: data.user.id, email: data.user.email ?? undefined, isAnonymous }, supabase }
}

export function cors(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, DELETE, OPTIONS",
  }
}

export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors() })
  return null
}

export function errorResponse(status: number, message: string, detail?: unknown): Response {
  return new Response(JSON.stringify({ error: message, detail }), {
    status,
    headers: { "Content-Type": "application/json", ...cors() },
  })
}

/**
 * A provider's refusal, passed on WITHOUT its billing status. 402 from this
 * app means "the learner's minutes are spent" and raises the paywall, so a
 * provider's 402 (our prepayment ran out, 2026-10-27) or 401/403 (our key)
 * must never reach the app as one: a paying subscriber was shown "your talk
 * time is used up" while it was our bill. Those become 503 (try again).
 */
export function upstreamErrorResponse(status: number, message: string, detail?: unknown): Response {
  const ours = status === 401 || status === 402 || status === 403
  return errorResponse(ours ? 503 : status >= 400 ? status : 502, message, detail)
}

/**
 * Constant-time string compare for shared secrets (cron/webhook headers), so a
 * `===` on an attacker-supplied value can't leak the secret one byte at a time
 * through response timing. Length is compared first (unavoidably non-secret),
 * then every byte is XOR-accumulated so the loop can't short-circuit early.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  const ab = new TextEncoder().encode(a)
  const bb = new TextEncoder().encode(b)
  if (ab.length !== bb.length) return false
  let diff = 0
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i]
  return diff === 0
}
