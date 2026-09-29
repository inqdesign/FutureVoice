// The admin console, served live.
//
// Every load reads production: one RPC to admin_raw(), assembled here into the
// page's data blob and injected into the shell. There is nothing to rebuild
// and nothing to remember to republish — which is the whole reason this
// exists (2026-09-04: the static artifact was found showing 8/27 numbers with
// three signups missing, because the gather had run and the republish hadn't).
//
// Since 2026-09-13 it also answers at https://nawana.app/admin — a Vercel
// rewrite (web/vercel.json) proxies that path to this Worker, so the browser
// stays on nawana.app and the cookie is a nawana.app cookie. Every path the
// Worker emits (form action, redirects, data.json) is therefore built on the
// BASE it was reached through: "/admin" behind the rewrite, "" on workers.dev.
//
// The page holds real names, real addresses and people's self-intros, so:
//   * the service-role key never leaves the Worker — the browser gets HTML,
//     never a token and never a Supabase call of its own;
//   * the door is a password form (ADMIN_PASSWORD, or ADMIN_TOKEN until one
//     is set) that trades for an HttpOnly cookie carrying a HASH of the
//     secret, never the secret itself; wrong guesses are throttled per IP;
//   * noindex and no-store, because a cached copy of this on a proxy is the
//     same leak as a shared link.
//
// There is NO cache: a reload is a fresh read of production, always. A 60 s
// hold was tried and retired on 2026-09-13 — on a launch day the whole point
// of a reload is to see the signup from a minute ago, and "it's cached" is
// exactly the class of silent staleness this console exists to end.

import shell from "./shell.html";
import { assemble } from "./assemble";
import { elevenTruth } from "./truth";

export interface Env {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  ADMIN_TOKEN: string;
  ADMIN_PASSWORD?: string;
  /** PostHog personal API key (scope: query read) — city + app-open state for
   *  the 라이브 tab. Without it the tab still works, with no map. */
  POSTHOG_API_KEY?: string;
  /** Numeric project id; defaults to the key's current project. */
  POSTHOG_PROJECT_ID?: string;
  /** ElevenLabs API key (the gateway's) — the 돈 tab's 실제 원가 reads the
   *  account's own usage, because the ledger sees under half of it (see
   *  truth.ts). Without it that section says how to set it; every other
   *  cost figure falls back to the ledger at the database's rate. */
  ELEVENLABS_API_KEY?: string;
}

const COOKIE = "nawana_admin";
const COOKIE_DAYS = 180;

// Failed logins per client IP. Per-isolate, so it is a speed bump rather than
// a wall — but a speed bump is what turns "guess the password" from minutes
// into years, and the secret is not a dictionary word.
const MAX_FAILS = 8;
const FAIL_WINDOW_MS = 15 * 60_000;
const fails = new Map<string, { n: number; until: number }>();

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function cookieValue(header: string | null, name: string): string | null {
  if (!header) return null;
  for (const part of header.split(";")) {
    const [k, ...v] = part.trim().split("=");
    if (k === name) return decodeURIComponent(v.join("="));
  }
  return null;
}

// What the cookie carries: a hash of the secret, so a leaked cookie jar does
// not hand over the password itself, and rotating the password logs every
// browser out at once.
async function sessionValue(secret: string): Promise<string> {
  const data = new TextEncoder().encode(`nawana-admin-session:${secret}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function secretOf(env: Env): string {
  return env.ADMIN_PASSWORD || env.ADMIN_TOKEN || "";
}

async function fetchData(env: Env) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/admin_raw`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  if (!r.ok) throw new Error(`admin_raw ${r.status}: ${(await r.text()).slice(0, 300)}`);
  const raw = await r.json() as any;
  // Per-user talk seconds and the ledger's own turn rows, for the cost table
  // (2026-09-26): the gateway's TTS never reaches the ledger, so a user's
  // talk cost is estimated from their seconds instead. Optional — without it
  // the table falls back to ledger characters, which see about half.
  raw.talk_cost = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/admin_talk_cost`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  }).then((t) => t.ok ? t.json() : null).catch((e) => {
    console.log(`admin_talk_cost: ${(e as Error).message}`);
    return null;
  });
  // Reply turns per (user, UTC day, UTC hour), so the heatmap can be drawn in
  // the reader's zone with its turn counts (2026-09-27). Optional — without it
  // the heatmap still draws, and its tooltip leaves the turn count out.
  raw.turn_hours = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/admin_turn_hours`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  }).then((t) => t.ok ? t.json() : null).catch((e) => {
    console.log(`admin_turn_hours: ${(e as Error).message}`);
    return null;
  });
  // Never let this card take the whole console down with it.
  raw.recent_ledger = await recentLedger(env).catch((e) => {
    console.log(`recentLedger: ${(e as Error).message}`);
    return [];
  });
  // ElevenLabs' own account of the window. Optional in every direction: no
  // key, a refused call or a rate-limited one leaves the tab on ledger
  // figures, marked as such.
  const truth = await elevenTruth(env, raw.windowStart).catch((e) => {
    console.log(`elevenTruth: ${(e as Error).message}`);
    return null;
  });
  const data = assemble(raw, truth);
  // Same rule as recentLedger: a missing column must not blank the console.
  const offers = await offerCodes(env).catch((e) => {
    console.log(`offerCodes: ${(e as Error).message}`);
    return {} as Record<string, OfferInfo>;
  });
  // Every profile's language pair — admin_raw's `setup` only has people who
  // finished setup after setup_at existed, which left the rest as "?".
  const langs = await profileLangs(env).catch((e) => {
    console.log(`profileLangs: ${(e as Error).message}`);
    return {} as Record<string, { native: string | null; target: string | null }>;
  });
  for (const u of data.users as { id: string; offer?: OfferInfo; native?: string | null; target?: string | null }[]) {
    if (offers[u.id]) u.offer = offers[u.id];
    if (langs[u.id]) { u.native = langs[u.id].native; u.target = langs[u.id].target; }
  }
  return data;
}

/** Every usage_ledger row of the last 24 h, thin, oldest first — the 라이브
 *  tab folds them into per-person episodes ("18:32–18:41 영어로 통화"). */
async function dayLedger(env: Env): Promise<unknown[]> {
  const since = new Date(Date.now() - 24 * 3_600_000).toISOString();
  const page = 1000;
  const rows: unknown[] = [];
  for (let from = 0; from < 20_000; from += page) {
    const url = `${env.SUPABASE_URL}/rest/v1/usage_ledger`
      + `?select=u:user_id,at:created_at,action,purpose:metadata->>purpose,`
      + `language:metadata->>language,seconds:metadata->seconds`
      + `&created_at=gte.${encodeURIComponent(since)}&user_id=not.is.null`
      + `&or=(source_fn.is.null,source_fn.neq.migration)&order=created_at.asc`;
    const r = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        Range: `${from}-${from + page - 1}`,
      },
    });
    if (!r.ok) throw new Error(`usage_ledger ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const batch = await r.json() as unknown[];
    rows.push(...batch);
    if (batch.length < page) break;
  }
  return rows;
}

async function profileLangs(env: Env): Promise<Record<string, { native: string | null; target: string | null }>> {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/profiles?select=id,native_language,target_language`, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
  });
  if (!r.ok) throw new Error(`profiles ${r.status}`);
  const out: Record<string, { native: string | null; target: string | null }> = {};
  for (const x of await r.json() as { id: string; native_language: string | null; target_language: string | null }[]) {
    out[x.id] = { native: x.native_language, target: x.target_language };
  }
  return out;
}

/** Who is on an App Store offer code (type 3), and at what price.
 *  Two sources, because Apple applies a code AFTER the free trial: during the
 *  trial week only renewal info knows about it (`renewal_offer_*`, filed from
 *  signedRenewalInfo since 20260918100000); once a period has been charged
 *  under it, the transaction carries `offer_type = 3` too. */
type OfferInfo = {
  name: string | null;
  price: number | null; currency: string | null;   // next charge, major units
  pending: boolean;                                  // code not charged yet
  firstChargedAt: string | null; charges: number;
};
async function offerCodes(env: Env): Promise<Record<string, OfferInfo>> {
  const get = async (q: string) => {
    const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${q}`, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    });
    if (!r.ok) throw new Error(`${q.split("?")[0]} ${r.status}: ${(await r.text()).slice(0, 200)}`);
    return await r.json() as Record<string, unknown>[];
  };
  const [subs, txs] = await Promise.all([
    get("user_subscriptions?select=user_id,renewal_offer_type,renewal_offer_id,"
      + "renewal_price_milliunits,renewal_currency&renewal_offer_type=eq.3"),
    get("subscription_transactions?select=user_id,purchase_date,price_milliunits,currency"
      + "&offer_type=eq.3&order=purchase_date.asc"),
  ]);
  const out: Record<string, OfferInfo> = {};
  const money = (m: unknown) => (typeof m === "number" ? m / 1000 : null);
  for (const t of txs) {
    const id = String(t.user_id);
    const o = out[id] ??= { name: null, price: money(t.price_milliunits),
      currency: (t.currency as string) ?? null, pending: false,
      firstChargedAt: (t.purchase_date as string) ?? null, charges: 0 };
    o.charges++;
  }
  for (const s of subs) {
    const id = String(s.user_id);
    const o = out[id] ??= { name: null, price: null, currency: null, pending: true,
      firstChargedAt: null, charges: 0 };
    o.name = (s.renewal_offer_id as string) ?? o.name;
    o.price = money(s.renewal_price_milliunits) ?? o.price;
    o.currency = (s.renewal_currency as string) ?? o.currency;
    o.pending = o.charges === 0;
  }
  return out;
}

/** Every usage_ledger row of the last 8 days, thin. `admin_raw.hours` is a
 *  whole-window UTC hour-of-day sum, which can say when people usually come
 *  but not what TODAY looks like against that — and "today" has to be cut in
 *  the zone the page is set to, so the rows go to the page raw and it buckets
 *  them. ~1k rows a day at launch; paged because PostgREST caps a response. */
async function recentLedger(env: Env): Promise<unknown[]> {
  const since = new Date(Date.now() - 8 * 86_400_000).toISOString();
  const page = 1000;
  const rows: unknown[] = [];
  for (let from = 0; from < 50_000; from += page) {
    const url = `${env.SUPABASE_URL}/rest/v1/usage_ledger`
      + `?select=user_id,created_at,action,delta,seconds:metadata->seconds`
      + `&created_at=gte.${encodeURIComponent(since)}&order=created_at.asc`;
    const r = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        Range: `${from}-${from + page - 1}`,
      },
    });
    if (!r.ok) throw new Error(`usage_ledger ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const batch = await r.json() as unknown[];
    rows.push(...batch);
    if (batch.length < page) break;
  }
  return rows;
}

// ---- PostHog: where people are, and whether the app is open --------------
// The iOS SDK stamps every event with a GeoIP city (PostHog's default) and
// sends "Application Opened" / "Application Backgrounded". One HogQL query
// reads the latest of each per account. distinct_id is the Supabase UUID
// UPPERCASED (Swift uuidString), so it is lowered to join.
//
// Held for 60 s per isolate: the tab polls every 15 s, a city does not move
// between two polls, and PostHog rate-limits its query API per project. The database half of live.json is never cached.
type PhRow = { city: string | null; cc: string | null; lat: number | null; lon: number | null;
               lifecycle: string | null; lifecycleAt: string | null;
               lastEvent: string | null; lastAt: string | null };
let phCache: { at: number; rows: Record<string, PhRow>; error?: string } | null = null;

async function posthogPresence(env: Env): Promise<{ rows: Record<string, PhRow>; error?: string }> {
  if (!env.POSTHOG_API_KEY) return { rows: {}, error: "no_key" };
  if (phCache && Date.now() - phCache.at < 60_000) return phCache;
  const project = env.POSTHOG_PROJECT_ID || "@current";
  const query = `
    select distinct_id,
      argMax(properties.$geoip_city_name, timestamp),
      argMax(properties.$geoip_country_code, timestamp),
      argMax(properties.$geoip_latitude, timestamp),
      argMax(properties.$geoip_longitude, timestamp),
      argMaxIf(event, timestamp, event in ('Application Opened', 'Application Backgrounded')),
      maxIf(timestamp, event in ('Application Opened', 'Application Backgrounded')),
      argMax(event, timestamp),
      max(timestamp)
    from events
    where timestamp > now() - interval 30 day
      and properties.app = 'nawana'
    group by distinct_id
    limit 10000`;
  try {
    const r = await fetch(`https://eu.posthog.com/api/projects/${project}/query/`, {
      method: "POST",
      headers: { Authorization: `Bearer ${env.POSTHOG_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query: { kind: "HogQLQuery", query } }),
    });
    if (!r.ok) throw new Error(`posthog ${r.status}`);
    const body = await r.json() as { results?: unknown[][] };
    const rows: Record<string, PhRow> = {};
    const iso = (v: unknown) => (v ? new Date(String(v).replace(" ", "T") + (String(v).match(/Z|[+-]\d\d:?\d\d$/) ? "" : "Z")).toISOString() : null);
    for (const x of body.results ?? []) {
      const id = String(x[0] ?? "").toLowerCase();
      if (!/^[0-9a-f-]{36}$/.test(id)) continue;
      const num = (v: unknown) => (v === null || v === "" || v === undefined ? null : Number(v));
      rows[id] = {
        city: (x[1] as string) || null, cc: (x[2] as string) || null,
        lat: num(x[3]), lon: num(x[4]),
        lifecycle: (x[5] as string) || null, lifecycleAt: iso(x[6]),
        lastEvent: (x[7] as string) || null, lastAt: iso(x[8]),
      };
    }
    phCache = { at: Date.now(), rows };
  } catch (e) {
    // Keep serving the last good answer; say that it is stale.
    phCache = { at: Date.now(), rows: phCache?.rows ?? {}, error: (e as Error).message };
  }
  return phCache;
}

const PRIVATE_HEADERS = {
  "Cache-Control": "no-store, private",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
};

const html = (body: string, status = 200, extra: Record<string, string> = {}) =>
  new Response(body, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8", ...PRIVATE_HEADERS, ...extra },
  });

const text = (body: string, status = 200) =>
  new Response(body, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", ...PRIVATE_HEADERS },
  });

function loginPage(base: string, message = ""): string {
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>nawana 어드민</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+KR:wght@400;600;700&display=swap">
<style>
:root{color-scheme:light;--page:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink-2:#52514e;--muted:#898781;
  --ring:rgba(11,11,11,.12);--s1:#2a78d6;--crit:#d03b3b}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--page);color:var(--ink);
  font-family:"IBM Plex Sans KR",system-ui,-apple-system,"Segoe UI",sans-serif;font-size:15px}
form{width:min(360px,calc(100vw - 32px));background:var(--surface);border:1px solid var(--ring);border-radius:12px;padding:26px 24px}
.eyebrow{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);font-weight:600;margin:0 0 6px}
h1{font-size:22px;margin:0 0 18px;letter-spacing:-.01em}
label{display:block;font-size:12.5px;color:var(--ink-2);font-weight:600;margin-bottom:6px}
input{width:100%;font:inherit;font-size:16px;padding:10px 12px;border:1px solid var(--ring);border-radius:8px;
  background:var(--page);color:var(--ink)}
input:focus{outline:2px solid var(--s1);outline-offset:1px;border-color:transparent}
button{margin-top:14px;width:100%;font:inherit;font-weight:600;font-size:15px;padding:10px;border:none;border-radius:8px;
  background:var(--ink);color:var(--page);cursor:pointer}
.msg{color:var(--crit);font-size:13px;margin:0 0 12px}
</style></head><body>
<form method="post" action="${base}/login" autocomplete="on">
  <p class="eyebrow">nawana · 내부 운영</p>
  <h1>어드민</h1>
  ${message ? `<p class="msg">${message}</p>` : ""}
  <label for="pw">비밀번호</label>
  <input id="pw" name="password" type="password" autocomplete="current-password" autofocus required>
  <button type="submit">들어가기</button>
</form></body></html>`;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    // Behind the nawana.app rewrite the path arrives as /admin/...; on
    // workers.dev it arrives bare. Strip the base once, remember it for
    // every path we hand back.
    const base = url.pathname === "/admin" || url.pathname.startsWith("/admin/") ? "/admin" : "";
    const path = url.pathname.slice(base.length) || "/";
    const secret = secretOf(env);
    if (!secret) return text("Not found", 404);

    const ip = req.headers.get("CF-Connecting-IP") ?? req.headers.get("x-real-ip") ?? "?";
    const cookieHeader = req.headers.get("Cookie");
    const expected = await sessionValue(secret);

    // ---- login -----------------------------------------------------------
    if (path === "/login" && req.method === "POST") {
      const bar = fails.get(ip);
      if (bar && bar.n >= MAX_FAILS && Date.now() < bar.until) {
        return html(loginPage(base, "잠시 뒤에 다시 시도해 주세요."), 429);
      }
      const form = await req.formData().catch(() => null);
      const given = String(form?.get("password") ?? "");
      if (!constantTimeEqual(given, secret)) {
        const cur = bar && Date.now() < bar.until ? bar : { n: 0, until: 0 };
        fails.set(ip, { n: cur.n + 1, until: Date.now() + FAIL_WINDOW_MS });
        await new Promise((r) => setTimeout(r, 600));
        return html(loginPage(base, "비밀번호가 맞지 않아요."), 401);
      }
      fails.delete(ip);
      return new Response(null, {
        status: 303,
        headers: {
          Location: base || "/",
          "Set-Cookie":
            `${COOKIE}=${expected}; HttpOnly; Secure; SameSite=Lax; Path=/; ` +
            `Max-Age=${60 * 60 * 24 * COOKIE_DAYS}`,
          ...PRIVATE_HEADERS,
        },
      });
    }
    if (path === "/logout") {
      return new Response(null, {
        status: 303,
        headers: {
          Location: base || "/",
          "Set-Cookie": `${COOKIE}=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0`,
          ...PRIVATE_HEADERS,
        },
      });
    }

    // The old ?k=<token> link still works: it is traded for the cookie and
    // redirected away, so the key leaves the address bar at once.
    const fromQuery = url.searchParams.get("k");
    if (fromQuery) {
      if (!constantTimeEqual(fromQuery, env.ADMIN_TOKEN ?? "") && !constantTimeEqual(fromQuery, secret)) {
        return text("Not found", 404);
      }
      const clean = new URL(url);
      clean.searchParams.delete("k");
      return new Response(null, {
        status: 302,
        headers: {
          Location: clean.pathname + clean.search,
          "Set-Cookie":
            `${COOKIE}=${expected}; HttpOnly; Secure; SameSite=Lax; Path=/; ` +
            `Max-Age=${60 * 60 * 24 * COOKIE_DAYS}`,
          ...PRIVATE_HEADERS,
        },
      });
    }

    const session = cookieValue(cookieHeader, COOKIE);
    const signedIn = !!session && constantTimeEqual(session, expected);
    if (!signedIn) {
      // data.json is for scripts, and a script gets a 404 rather than a form.
      if (path === "/data.json" || path === "/live.json") return text("Not found", 404);
      return html(loginPage(base), 401);
    }

    if (!env.SUPABASE_SERVICE_ROLE_KEY) {
      return text(
        "SUPABASE_SERVICE_ROLE_KEY가 아직 없어요. (비밀번호는 설정돼 있어요 —\n" +
        "이 화면이 보인다는 게 그 증거예요.)\n\n" +
        "  bash admin/deploy.sh secret SUPABASE_SERVICE_ROLE_KEY\n\n" +
        "키는 Supabase 대시보드 → Project Settings → API keys → service_role.\n",
        503,
      );
    }

    // The 라이브 tab polls this every 15 s — its own small RPC, never the whole
    // admin_raw() read the page itself is built from.
    if (path === "/live.json") {
      const [r, ph] = await Promise.all([
        fetch(`${env.SUPABASE_URL}/rest/v1/rpc/admin_live`, {
          method: "POST",
          headers: {
            apikey: env.SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
          },
          body: "{}",
        }),
        posthogPresence(env),
      ]);
      if (!r.ok) {
        return new Response(JSON.stringify({ error: `admin_live ${r.status}` }), {
          status: 502,
          headers: { "Content-Type": "application/json; charset=utf-8", ...PRIVATE_HEADERS },
        });
      }
      const live = await r.json() as Record<string, unknown>;
      // The timeline needs every row of the day, not admin_live's last 12 per
      // person — a call alone writes a talk tick every 15 s.
      const events = await dayLedger(env).catch((e) => {
        console.log(`dayLedger: ${(e as Error).message}`);
        return [];
      });
      return new Response(JSON.stringify({ ...live, events, ph: ph.rows, phError: ph.error ?? null }), {
        headers: { "Content-Type": "application/json; charset=utf-8", ...PRIVATE_HEADERS },
      });
    }

    let data: unknown;
    try {
      data = await fetchData(env);
    } catch (e) {
      return text(`데이터를 읽지 못했어요\n\n${(e as Error).message}\n`, 502);
    }

    if (path === "/data.json") {
      return new Response(JSON.stringify(data), {
        headers: { "Content-Type": "application/json; charset=utf-8", ...PRIVATE_HEADERS },
      });
    }

    const page = (shell as unknown as string)
      .replace("__ADMIN_DATA__", () => JSON.stringify(data))
      .replaceAll("__ADMIN_BASE__", base);
    return html(page);
  },
};
