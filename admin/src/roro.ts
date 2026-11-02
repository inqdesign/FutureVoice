// Dear RoRo, in the same console (2026-10-25).
//
// The owner wanted one place for both apps, built as a copy of nawana's page
// first and redesigned together after. So this is the nawana pattern again —
// every load reads production, no cache, the service-role key never leaves
// the Worker — pointed at Dear RoRo's Supabase project instead.
//
// What lives where:
//   * 1.x (React Native, the app in the store) — everything is in Supabase:
//     profiles, children, memories, stories, recordings, app_sessions.
//   * 2.0 (SwiftUI, docs/SPEC.md in the DearRoRo repo) — the journal never
//     leaves the phone, so the server only sees story_usage / story_voices,
//     and behaviour goes to PostHog with `app = dearroro` (same project as
//     nawana, which is why POSTHOG_API_KEY works for both). Its distinct_id is
//     a keychain id, NOT a Supabase user id, so 2.0's PostHog numbers are
//     shown on their own and never joined to a person row.
//
// No migration is needed: the tables are small (app_sessions, the biggest,
// is ~13k rows), so they are read thin through PostgREST and folded here.
// Memory text, story text and titles are never read — counts and times only.

export interface RoroEnv {
  DEARRORO_SUPABASE_URL?: string;
  DEARRORO_SERVICE_ROLE_KEY?: string;
  POSTHOG_API_KEY?: string;
  POSTHOG_PROJECT_ID?: string;
}

const DAY = 86_400_000;
/** Session rows newer than this go to the page raw, so it can bucket them
 *  into days and hours in the reader's zone. Older ones are only counted. */
const RAW_SESSION_DAYS = 120;

type Row = Record<string, any>;

async function rest(env: RoroEnv, path: string, maxRows = 50_000): Promise<Row[]> {
  const rows: Row[] = [];
  const page = 1000;
  for (let from = 0; from < maxRows; from += page) {
    const r = await fetch(`${env.DEARRORO_SUPABASE_URL}/rest/v1/${path}`, {
      headers: {
        apikey: env.DEARRORO_SERVICE_ROLE_KEY!,
        Authorization: `Bearer ${env.DEARRORO_SERVICE_ROLE_KEY}`,
        Range: `${from}-${from + page - 1}`,
      },
    });
    if (!r.ok) throw new Error(`${path.split("?")[0]} ${r.status}: ${(await r.text()).slice(0, 200)}`);
    const batch = await r.json() as Row[];
    rows.push(...batch);
    if (batch.length < page) break;
  }
  return rows;
}

/** A read the page can live without: logged, and an empty answer. */
const optional = <T>(name: string, p: Promise<T>, empty: T): Promise<T> =>
  p.catch((e) => { console.log(`roro ${name}: ${(e as Error).message}`); return empty; });

/** Auth's own view (anonymous flag, provider, last sign-in). Optional and
 *  page by page: on 2026-10-25 this project's admin users API answered 500
 *  "Database error finding users" for any page holding certain rows, so a
 *  failed page is skipped rather than failing the list — profiles is the
 *  list, this only fills in. */
async function authUsers(env: RoroEnv): Promise<Row[]> {
  const out: Row[] = [];
  const per = 50;
  for (let page = 1; page < 200; page++) {
    const r = await fetch(`${env.DEARRORO_SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=${per}`, {
      headers: {
        apikey: env.DEARRORO_SERVICE_ROLE_KEY!,
        Authorization: `Bearer ${env.DEARRORO_SERVICE_ROLE_KEY}`,
      },
    });
    const total = Number(r.headers.get("x-total-count") || 0);
    if (r.ok) {
      const users = ((await r.json()) as { users?: Row[] }).users ?? [];
      out.push(...users);
      if (users.length < per) break;
    } else {
      console.log(`roro auth users page ${page}: ${r.status}`);
      if (!total || page * per >= total) break;
    }
  }
  return out;
}

async function hogql(env: RoroEnv, query: string): Promise<unknown[][]> {
  if (!env.POSTHOG_API_KEY) throw new Error("no_key");
  const project = env.POSTHOG_PROJECT_ID || "@current";
  const r = await fetch(`https://eu.posthog.com/api/projects/${project}/query/`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.POSTHOG_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query: { kind: "HogQLQuery", query } }),
  });
  if (!r.ok) throw new Error(`posthog ${r.status}`);
  return ((await r.json()) as { results?: unknown[][] }).results ?? [];
}

/** PostHog's timestamps come back without a zone; they are UTC. */
const phTime = (v: unknown) => v == null ? null
  : new Date(String(v).replace(" ", "T") + (/Z|[+-]\d\d:?\d\d$/.test(String(v)) ? "" : "Z")).toISOString();

/** The owner's own phones (PostHog ids): store/TestFlight builds, so not
 *  tagged `dev_build`, but not users either. */
const OWNER_DEVICES = ["6082DF7E-2AE3-4B5E-9D70-5A26C3D2CD15"];

/** 2.0's events. Development builds tag every event `dev_build` and are left
 *  out, the same filter the PostHog dashboard uses (SPEC §3.5c). */
async function v2Events(env: RoroEnv) {
  const real = `properties.app = 'dearroro' and properties.dev_build is null
        and distinct_id not in (${OWNER_DEVICES.map((d) => `'${d}'`).join(", ")})`;
  /* Who came from 1.x: the app shows the "bring my memories" screen only when
   * 1.x's session is still on the phone (DearRoRo LegacyImport.swift), and
   * every step of it sends a legacy_* event. moved = brought them in,
   * stayed = saw the screen but didn't (fresh, failed, or not chosen yet). */
  const cohort = `multiIf(
        distinct_id in (select distinct_id from events where ${real} and event = 'legacy_import_done'), 'moved',
        distinct_id in (select distinct_id from events where ${real} and startsWith(event, 'legacy_')), 'stayed',
        'new')`;
  const [byEvent, byDay, steps, legacy] = await Promise.all([
    hogql(env, `
      select event, ${cohort} as cohort, count(), uniq(distinct_id), max(timestamp),
        countIf(timestamp > now() - interval 7 day)
      from events
      where ${real}
        and not startsWith(event, '$')
      group by event, cohort order by count() desc limit 600`),
    hogql(env, `
      select toString(toDate(timestamp)), ${cohort} as cohort, uniq(distinct_id), count()
      from events
      where ${real}
        and timestamp > now() - interval 90 day
      group by toDate(timestamp), cohort order by toDate(timestamp) limit 600`),
    hogql(env, `
      select properties.step, uniq(distinct_id)
      from events
      where ${real}
        and event = 'onboarding_step'
      group by properties.step limit 50`),
    // One row per way the 1.x screen ended. A failed import shows the screen
    // again next launch, so a later success counts as moved.
    hogql(env, `
      select multiIf(done, 'moved', fresh, 'fresh', failed, 'failed', 'pending') as how,
        count(), sum(days), sum(memories)
      from (
        select distinct_id,
          countIf(event = 'legacy_import_done') > 0 as done,
          countIf(event = 'legacy_choice' and properties.choice = 'fresh') > 0 as fresh,
          countIf(event = 'legacy_import_failed') > 0 as failed,
          maxIf(toInt(properties.days), event = 'legacy_import_done') as days,
          maxIf(toInt(properties.memories), event = 'legacy_import_done') as memories
        from events
        where ${real}
          and startsWith(event, 'legacy_')
        group by distinct_id)
      group by how limit 10`),
  ]);
  return {
    events: byEvent.map((x) => ({ event: String(x[0]), cohort: String(x[1]), n: Number(x[2]), people: Number(x[3]),
      last: phTime(x[4]), n7: Number(x[5]) })),
    days: byDay.map((x) => ({ day: String(x[0]), cohort: String(x[1]), people: Number(x[2]), n: Number(x[3]) })),
    steps: steps.map((x) => ({ step: x[0] == null ? null : String(x[0]), people: Number(x[1]) })),
    legacy: legacy.map((x) => ({ how: String(x[0]), people: Number(x[1]), days: Number(x[2] ?? 0),
      memories: Number(x[3] ?? 0) })),
  };
}

export async function roroData(env: RoroEnv) {
  if (!env.DEARRORO_SUPABASE_URL || !env.DEARRORO_SERVICE_ROLE_KEY) {
    throw new Error("DEARRORO_SERVICE_ROLE_KEY가 아직 없어요 — bash admin/deploy.sh secret DEARRORO_SERVICE_ROLE_KEY");
  }
  const [auth, profiles, excluded, children, memories, stories, recordings, sessions,
         daily, credits, storyUsage, voices, v2] = await Promise.all([
    optional("auth", authUsers(env), [] as Row[]),
    rest(env, "profiles?select=id,name,email,created_at,last_seen_at,last_active_at,"
      + "subscription_status,subscription_period_type,subscription_will_renew,subscription_expires_at,"
      + "subscription_started_at,subscription_source,last_app_version,last_app_build,app_language,"
      + "parenting_country,is_admin,auth_provider,beta_tester,referred_by,family_code"),
    optional("excluded", fetch(`${env.DEARRORO_SUPABASE_URL}/rest/v1/rpc/admin_excluded_ids`, {
      method: "POST",
      headers: {
        apikey: env.DEARRORO_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.DEARRORO_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    }).then(async (r) => {
      if (!r.ok) throw new Error(String(r.status));
      // SETOF uuid comes back as a bare array of strings.
      return ((await r.json()) as unknown[]).map((x) => typeof x === "string" ? x : String(Object.values(x as Row)[0]));
    }), [] as string[]),
    rest(env, "children?select=u:user_id,subject:subject_type,at:created_at"),
    rest(env, "memories?select=u:user_id,at:created_at,video:has_video,kind:memory_type&order=created_at.asc"),
    rest(env, "stories?select=u:user_id,at:created_at,type:story_type,source:story_source&order=created_at.asc"),
    optional("recordings", rest(env, "recorded_stories?select=u:user_id,at:created_at&order=created_at.asc"), []),
    rest(env, "app_sessions?select=u:user_id,at:started_at,secs:duration_seconds&order=started_at.asc", 200_000),
    optional("daily", rest(env, "daily_record_events?select=u:user_id,at:recorded_at,type&order=recorded_at.asc"), []),
    optional("credits", rest(env, "story_credit_transactions?select=u:user_id,at:created_at,type:transaction_type,"
      + "amount:credits_amount,product:product_id&order=created_at.asc"), []),
    optional("story_usage", rest(env, "story_usage?select=u:user_id,at:created_at,type,language,paid:paid_with&order=created_at.asc"), []),
    optional("story_voices", rest(env, "story_voices?select=u:user_id,at:created_at,removed:removed_at,shared,language"), []),
    optional("posthog", v2Events(env), null),
  ]);

  // One row per account. profiles is the list (every 1.x account has one);
  // 2.0's anonymous accounts have none, so anyone who made a 2.0 story or
  // voice is added from auth, or from those rows alone when auth failed.
  const authById = new Map(auth.map((a) => [a.id as string, a]));
  const ids = [...profiles.map((p) => p.id as string)];
  const seen = new Set(ids);
  for (const r of [...auth.filter((a) => a.is_anonymous), ...storyUsage, ...voices]) {
    const id = (r.id ?? r.u) as string;
    if (!seen.has(id)) { seen.add(id); ids.push(id); }
  }
  const prof = new Map(profiles.map((p) => [p.id, p]));
  const users = ids.map((id) => {
    const p = prof.get(id) ?? {};
    const a = authById.get(id) ?? {};
    const firstV2 = [...storyUsage, ...voices].filter((r) => r.u === id).map((r) => r.at as string).sort()[0];
    return {
      id,
      name: (p.name as string) || null,
      email: (p.email as string) || (a.email as string) || null,
      provider: (a.app_metadata?.provider as string) || (p.auth_provider as string) || null,
      anon: a.is_anonymous === true || !prof.has(id),
      hasProfile: prof.has(id),
      createdAt: (p.created_at as string) || (a.created_at as string) || firstV2 || null,
      lastSignIn: (a.last_sign_in_at as string) || null,
      lastSeen: (p.last_seen_at as string) || (p.last_active_at as string) || null,
      tier: (p.subscription_status as string) || "free",
      period: (p.subscription_period_type as string) || null,
      willRenew: p.subscription_will_renew ?? null,
      subExpires: (p.subscription_expires_at as string) || null,
      subStarted: (p.subscription_started_at as string) || null,
      subSource: (p.subscription_source as string) || null,
      version: (p.last_app_version as string) || null,
      build: p.last_app_build ?? null,
      lang: (p.app_language as string) || null,
      country: (p.parenting_country as string) || null,
      admin: !!p.is_admin,
      beta: !!p.beta_tester,
      referred: !!p.referred_by,
      family: (p.family_code as string) || null,
    };
  });
  const idx = new Map(users.map((u, i) => [u.id, i]));
  const key = <T extends Row>(rows: T[]) => rows.filter((r) => idx.has(r.u)).map((r) => ({ ...r, u: idx.get(r.u)! }));

  // Sessions: per-person totals over all time, raw rows for the recent window.
  const since = Date.now() - RAW_SESSION_DAYS * DAY;
  const sessTotals = new Map<number, { n: number; secs: number; first: string; last: string; days: Set<string> }>();
  const recentSessions: Array<{ u: number; at: string; secs: number }> = [];
  for (const s of sessions) {
    const u = idx.get(s.u); if (u === undefined) continue;
    const secs = Math.max(0, Math.min(Number(s.secs) || 0, 4 * 3600));   // a stint left open overnight
    const t = sessTotals.get(u) ?? { n: 0, secs: 0, first: s.at, last: s.at, days: new Set() };
    t.n++; t.secs += secs; t.last = s.at; t.days.add(String(s.at).slice(0, 10));
    sessTotals.set(u, t);
    if (Date.parse(s.at) >= since) recentSessions.push({ u, at: s.at, secs });
  }

  return {
    asOf: new Date().toISOString(),
    rawSessionDays: RAW_SESSION_DAYS,
    excluded: excluded.filter((id) => idx.has(id)).map((id) => idx.get(id)!),
    users: users.map((u, i) => {
      const t = sessTotals.get(i);
      return { ...u, sessions: t?.n ?? 0, sessionSecs: t?.secs ?? 0, firstSession: t?.first ?? null,
               lastSession: t?.last ?? null, activeDays: t?.days.size ?? 0 };
    }),
    children: key(children),
    memories: key(memories),
    stories: key(stories),
    recordings: key(recordings),
    sessions: recentSessions,
    daily: key(daily),
    credits: key(credits),
    storyUsage: key(storyUsage),
    voices: key(voices),
    v2,
  };
}
