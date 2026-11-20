// The 크리에이터 page's server half: nawana.app/admin/creators.
//
// Applications come in through the public page (web/creators.html →
// creator-apply). Everything here is behind the console's session, and the
// tables are RLS-locked with no policies, so they are read and written with
// the service-role key, which never leaves the Worker.
//
// What an application turns into:
//   new → talking (the founder DMed them) → active (a code was made)
//       → paused / ended, or declined at any point before.
//
// The free access is a STANDING comp code: it rolls every month with its pool
// refilled, so a creator who keeps going is no monthly chore. Ending someone
// sets cancel_at_period_end on their comp row and the nightly sweep ends it on
// the last day of the period. A learner can redeem only ONE comp code ever, so
// a code is remade only while nobody has redeemed it.
//
// Applicants' text is untrusted. It is served as JSON only and the page puts
// it on screen through textContent, because this page holds the session that
// can write here.

export interface CreatorsEnv {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, private",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const STATUSES = ["new", "talking", "active", "paused", "declined"];
const PLANS = ["light_monthly", "plus_monthly"];
// No 0/O or 1/I: this gets read off a DM and typed by hand.
const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const DAYS_SHOWN = 21;
// The challenge package: three months that are judged, and ten days on the house.
const CHALLENGE_DAYS = 100;
const CHALLENGE_PLANS = ["light_challenge", "plus_challenge", "max_challenge"];

class Missing extends Error {}

async function rest(env: CreatorsEnv, path: string, init: RequestInit = {}): Promise<any> {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
  if (r.status === 404) throw new Missing();
  const body = await r.text();
  if (!r.ok) {
    if (body.includes("PGRST205") || body.includes("does not exist")) throw new Missing();
    throw new Error(`${path.split("?")[0]} ${r.status}: ${body.slice(0, 200)}`);
  }
  return body ? JSON.parse(body) : null;
}

/** Same lock as the marketing buttons: JSON only, and from this very page. */
function sameOrigin(req: Request): boolean {
  if (!(req.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/json")) return false;
  const site = req.headers.get("Sec-Fetch-Site");
  if (site && site !== "same-origin") return false;
  const origin = req.headers.get("Origin");
  if (origin) {
    let host: string;
    try { host = new URL(origin).host; } catch { return false; }
    const here = new URL(req.url).host;
    if (host !== here && host !== "nawana.app" && host !== "www.nawana.app") return false;
  }
  return true;
}

const inList = (xs: string[]) => `in.(${xs.map((x) => `"${x}"`).join(",")})`;

function newCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

// ---------------------------------------------------------------- read

export async function creatorsData(env: CreatorsEnv): Promise<Response> {
  try {
    const apps = await rest(env, "creator_applications?select=*&order=created_at.desc&limit=1000") as any[];
    const since = new Date(Date.now() - (DAYS_SHOWN + 1) * 86_400_000).toISOString().slice(0, 10);
    const ids = apps.map((a) => a.id);
    const codes = apps.map((a) => a.comp_code).filter(Boolean) as string[];

    const [posts, redemptions] = await Promise.all([
      ids.length ? rest(env, `creator_posts?select=application_id,day&day=gte.${since}`) : [],
      codes.length ? rest(env, `comp_redemptions?select=code,user_id,created_at&code=${inList(codes)}`) : [],
    ]) as [any[], any[]];

    // A creator is known by the code they redeemed, a challenger by the account that paid.
    const payers = apps.map((a) => a.user_id).filter(Boolean) as string[];
    const users = [...new Set([...redemptions.map((r) => r.user_id) as string[], ...payers])];
    const config = await rest(env, "billing_config?select=challenge_starts_at&limit=1").catch(() => []) as any[];
    const cohortStart: string | null = config[0]?.challenge_starts_at ?? null;
    // A challenger's months are judged over the whole challenge, so their talk is read from its first day.
    const longSince = cohortStart && cohortStart.slice(0, 10) < since ? cohortStart.slice(0, 10) : since;
    const [subs, talk] = await Promise.all([
      users.length ? rest(env, `user_subscriptions?select=user_id,plan_id,status,source,current_period_end,cancel_at_period_end&user_id=${inList(users)}`) : [],
      users.length ? rest(env, `talk_seconds_by_language?select=user_id,day,seconds&user_id=${inList(users)}&day=gte.${payers.length ? longSince : since}&limit=20000`) : [],
    ]) as [any[], any[]];

    // What a challenger's own phone said about each of their days: talk and
    // speech takes by the date where they live. Read from a day before the
    // cohort's first Seoul day, and by pages, since 100 days of a few people is
    // past one answer's row limit. A database without the table yet reads as
    // nobody having checked in, and the page falls back to the talk ledger.
    const daysSince = cohortStart
      ? new Date(Date.parse(cohortStart) + 9 * 3_600_000 - 86_400_000).toISOString().slice(0, 10)
      : since;
    const checkins: any[] = [];
    if (payers.length) {
      for (let offset = 0; offset < 50_000; offset += 1000) {
        const page = await rest(env, `challenge_days?select=user_id,day,talk_seconds,speech_takes&user_id=${inList([...new Set(payers)])}&day=gte.${daysSince}&order=user_id,day&limit=1000&offset=${offset}`).catch(() => []) as any[];
        checkins.push(...page);
        if (page.length < 1000) break;
      }
    }

    const byCode = new Map(redemptions.map((r) => [r.code, r]));
    const subOf = new Map(subs.map((s) => [s.user_id, s]));
    const out = apps.map((a) => {
      const red = a.comp_code ? byCode.get(a.comp_code) : undefined;
      const talkByDay: Record<string, number> = {};
      const who = red?.user_id ?? a.user_id ?? null;
      if (who) for (const t of talk) if (t.user_id === who) talkByDay[t.day] = (talkByDay[t.day] ?? 0) + t.seconds;
      const days: Record<string, { talk: number; speech: number }> = {};
      if (a.user_id) for (const c of checkins) if (c.user_id === a.user_id) days[c.day] = { talk: c.talk_seconds, speech: c.speech_takes };
      return {
        ...a,
        contact_key: undefined,
        redeemed_at: red?.created_at ?? null,
        subscription: who ? subOf.get(who) ?? null : null,
        talk: talkByDay,
        days,
        posts: posts.filter((p) => p.application_id === a.id).map((p) => p.day),
      };
    });
    // The page's guestbook. Its own table, so a database without it still shows the applications.
    const notes = await rest(env, "creator_notes?select=id,body,hidden,created_at&order=created_at.desc&limit=300").catch(() => []) as any[];
    return json({ apps: out, notes, days: DAYS_SHOWN, cohort_start: cohortStart, now: new Date().toISOString() });
  } catch (e) {
    if (e instanceof Missing) return json({ apps: [], missing: true, days: DAYS_SHOWN });
    return json({ error: (e as Error).message }, 502);
  }
}

// ---------------------------------------------------------------- write

async function patch(env: CreatorsEnv, id: string, fields: Record<string, unknown>) {
  const rows = await rest(env, `creator_applications?id=eq.${id}`, {
    method: "PATCH",
    body: JSON.stringify({ ...fields, updated_at: new Date().toISOString() }),
  }) as any[];
  return rows[0] ?? null;
}

/** The learner's comp row, if they ever redeemed this application's code. */
async function compUser(env: CreatorsEnv, code: string | null): Promise<string | null> {
  if (!code) return null;
  const rows = await rest(env, `comp_redemptions?select=user_id&code=eq.${encodeURIComponent(code)}`) as any[];
  return rows[0]?.user_id ?? null;
}

async function setCompEnding(env: CreatorsEnv, userId: string, ending: boolean) {
  await rest(env, `user_subscriptions?user_id=eq.${userId}&source=eq.comp`, {
    method: "PATCH",
    body: JSON.stringify({ cancel_at_period_end: ending, updated_at: new Date().toISOString() }),
  });
}

export async function creatorsAction(req: Request, env: CreatorsEnv, id: string, action: string): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!sameOrigin(req)) return json({ error: "origin" }, 403);
  if (!UUID.test(id)) return json({ error: "bad_id" }, 400);
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;

  try {
    // A guestbook line: hidden from the page, or shown again. The id is the note's.
    if (action === "note-hide" || action === "note-show") {
      await rest(env, `creator_notes?id=eq.${id}`, {
        method: "PATCH", headers: { Prefer: "return=minimal" },
        body: JSON.stringify({ hidden: action === "note-hide" }),
      });
      return json({ ok: true });
    }

    const found = await rest(env, `creator_applications?select=*&id=eq.${id}`) as any[];
    const app = found[0];
    if (!app) return json({ error: "not_found" }, 404);
    const now = new Date().toISOString();

    if (action === "note") {
      const note = String(body.note ?? "").slice(0, 4000);
      return json({ ok: true, app: await patch(env, id, { note: note || null }) });
    }

    if (action === "status") {
      const status = String(body.status ?? "");
      if (!STATUSES.includes(status)) return json({ error: "bad_status" }, 400);
      const fields: Record<string, unknown> = { status };
      if (status === "active") {
        fields.ended_at = null;
        fields.started_at = app.started_at ?? now;
        // Coming back from an ending: the comp goes on rolling.
        const user = await compUser(env, app.comp_code);
        if (user) await setCompEnding(env, user, false);
      }
      return json({ ok: true, app: await patch(env, id, fields) });
    }

    if (action === "code") {
      const plan = String(body.plan ?? "");
      if (!PLANS.includes(plan)) return json({ error: "bad_plan" }, 400);
      if (await compUser(env, app.comp_code)) return json({ error: "already_redeemed" }, 409);
      // An unused code is retired rather than left working beside the new one.
      if (app.comp_code) {
        await rest(env, `comp_codes?code=eq.${encodeURIComponent(app.comp_code)}`, {
          method: "PATCH", body: JSON.stringify({ expires_at: now }),
        });
      }
      const expires = new Date(Date.now() + 30 * 86_400_000).toISOString();
      let code = "";
      for (let tries = 0; ; tries++) {
        code = newCode();
        const r = await fetch(`${env.SUPABASE_URL}/rest/v1/comp_codes`, {
          method: "POST",
          headers: {
            apikey: env.SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            code, plan_id: plan, months: 1, max_redemptions: 1,
            standing: true, replaces_free_minutes: true,
            note: `creator program: ${String(app.contact).slice(0, 80)}`,
            expires_at: expires,
          }),
        });
        if (r.ok) break;
        if (r.status !== 409 || tries >= 3) throw new Error(`comp_codes ${r.status}: ${(await r.text()).slice(0, 200)}`);
      }
      const row = await patch(env, id, { comp_code: code, status: "active", started_at: app.started_at ?? now, ended_at: null });
      return json({ ok: true, app: row, code });
    }

    if (action === "post") {
      const day = String(body.day ?? "");
      if (!DAY.test(day)) return json({ error: "bad_day" }, 400);
      if (body.on) {
        await rest(env, "creator_posts?on_conflict=application_id,day", {
          method: "POST",
          headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
          body: JSON.stringify({ application_id: id, day }),
        });
      } else {
        await rest(env, `creator_posts?application_id=eq.${id}&day=eq.${day}`, { method: "DELETE" });
      }
      return json({ ok: true });
    }

    if (action === "end") {
      const user = await compUser(env, app.comp_code);
      if (user) await setCompEnding(env, user, true);
      return json({ ok: true, app: await patch(env, id, { status: "ended", ended_at: now }) });
    }

    // The challenger's reward: each month kept is one free month, given once by
    // moving the end of the package they paid for. 0 is a decision too.
    if (action === "reward") {
      const months = Number(body.months);
      if (!Number.isInteger(months) || months < 0 || months > 3) return json({ error: "bad_months" }, 400);
      if (app.kind !== "challenger" || !app.user_id) return json({ error: "not_paid" }, 409);
      if (app.rewarded_at) return json({ error: "already_rewarded" }, 409);
      if (months > 0) {
        const rows = await rest(env, `user_subscriptions?select=plan_id,source,stripe_subscription_id,current_period_end&user_id=eq.${app.user_id}`) as any[];
        const sub = rows[0];
        // Only the package itself is lengthened. Someone who has since moved to a store subscription is a person's call.
        if (!sub || sub.source !== "stripe" || sub.stripe_subscription_id || !CHALLENGE_PLANS.includes(sub.plan_id)) {
          return json({ error: "no_package" }, 409);
        }
        const from = new Date(Math.max(Date.parse(sub.current_period_end ?? now), Date.now()));
        from.setUTCMonth(from.getUTCMonth() + months);
        await rest(env, `user_subscriptions?user_id=eq.${app.user_id}`, {
          method: "PATCH",
          body: JSON.stringify({ status: "active", cancel_at_period_end: true, current_period_end: from.toISOString(), updated_at: now }),
        });
      }
      return json({ ok: true, app: await patch(env, id, { reward_months: months, rewarded_at: now }) });
    }

    // What moving up costs, and the checkout to send: both come from the
    // challenge-upgrade function, which holds the prices and the Stripe key.
    // When the challenger pays, stripe-webhook changes the package by itself.
    if (action === "upgrade-quote" || action === "upgrade-link") {
      const r = await fetch(`${env.SUPABASE_URL}/functions/v1/challenge-upgrade`, {
        method: "POST",
        headers: { Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, apikey: env.SUPABASE_SERVICE_ROLE_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ application_id: id, target: String(body.plan ?? ""), make: action === "upgrade-link" }),
      });
      const out = await r.json().catch(() => ({})) as Record<string, unknown>;
      return json(r.ok ? out : { error: out.error ?? "upgrade_failed" }, r.ok ? 200 : r.status === 404 ? 503 : r.status);
    }

    // Talk time on top, from the founder: it goes where every extra minute lives
    // (user_credits.balance, spent before the plan's pool) and is written in the ledger.
    if (action === "minutes") {
      const minutes = Number(body.minutes);
      if (![30, 60, 120, 300].includes(minutes)) return json({ error: "bad_minutes" }, 400);
      const who = app.user_id ?? await compUser(env, app.comp_code);
      if (!who) return json({ error: "no_account" }, 409);
      await rest(env, "rpc/grant_credits", {
        method: "POST",
        body: JSON.stringify({
          p_user_id: who, p_credits: minutes * 60, p_kind: "grant", p_action: "founder_grant", p_source_fn: "nawana-admin",
          p_idempotency_key: `program-grant:${id}:${Date.now()}`,
          p_metadata: { reason: "extra talk minutes from the founder", application_id: id },
        }),
      });
      return json({ ok: true, app: await patch(env, id, { extra_seconds: (app.extra_seconds ?? 0) + minutes * 60 }) });
    }

    // A challenger who needs more talk moves up a size. The difference is settled
    // with the founder by hand; this only changes the package they hold. Its
    // dates stay, and the new pool counts from the same month.
    if (action === "upgrade") {
      const plan = String(body.plan ?? "");
      if (!CHALLENGE_PLANS.includes(plan)) return json({ error: "bad_plan" }, 400);
      if (app.kind !== "challenger" || !app.user_id) return json({ error: "not_paid" }, 409);
      const rows = await rest(env, `user_subscriptions?select=plan_id,source,stripe_subscription_id&user_id=eq.${app.user_id}`) as any[];
      const sub = rows[0];
      if (!sub || sub.source !== "stripe" || sub.stripe_subscription_id || !CHALLENGE_PLANS.includes(sub.plan_id)) {
        return json({ error: "no_package" }, 409);
      }
      await rest(env, `user_subscriptions?user_id=eq.${app.user_id}`, {
        method: "PATCH", body: JSON.stringify({ plan_id: plan, updated_at: now }),
      });
      return json({ ok: true, app: await patch(env, id, { paid_plan: plan }) });
    }

    // The page promises this: gone when the program ends or when they ask.
    // Their account and any comp they redeemed are separate and stay.
    if (action === "delete") {
      if (!["ended", "declined"].includes(app.status)) return json({ error: "still_open" }, 409);
      await rest(env, `creator_applications?id=eq.${id}`, { method: "DELETE" });
      return json({ ok: true, deleted: true });
    }

    return json({ error: "unknown_action" }, 404);
  } catch (e) {
    if (e instanceof Missing) return json({ error: "tables_missing" }, 503);
    return json({ error: (e as Error).message }, 502);
  }
}

/** Cohort 1's first day. Saved for the webhook, and every package already paid is moved to run its 100 days from it. */
export async function creatorsCohort(req: Request, env: CreatorsEnv): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!sameOrigin(req)) return json({ error: "origin" }, 403);
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const day = String(body.day ?? "");
  if (!DAY.test(day)) return json({ error: "bad_day" }, 400);
  try {
    // The cohort is Korean: the day begins at midnight in Seoul.
    const start = new Date(`${day}T00:00:00+09:00`);
    if (isNaN(start.getTime())) return json({ error: "bad_day" }, 400);
    const end = new Date(start.getTime() + CHALLENGE_DAYS * 86_400_000);
    await rest(env, "billing_config?id=eq.true", {
      method: "PATCH", body: JSON.stringify({ challenge_starts_at: start.toISOString() }),
    });
    // Packages not yet rewarded only: a reward has already been added on top of the end date.
    const paid = await rest(env, "creator_applications?select=user_id&kind=eq.challenger&user_id=not.is.null&rewarded_at=is.null") as any[];
    const users = paid.map((p) => p.user_id) as string[];
    let moved = 0;
    if (users.length) {
      const rows = await rest(env, `user_subscriptions?user_id=${inList(users)}&source=eq.stripe&stripe_subscription_id=is.null&plan_id=${inList(CHALLENGE_PLANS)}`, {
        method: "PATCH",
        body: JSON.stringify({ current_period_end: end.toISOString(), status: "active", updated_at: new Date().toISOString() }),
      }) as any[];
      moved = rows.length;
    }
    return json({ ok: true, cohort_start: start.toISOString(), moved });
  } catch (e) {
    if (e instanceof Missing) return json({ error: "tables_missing" }, 503);
    return json({ error: (e as Error).message }, 502);
  }
}
