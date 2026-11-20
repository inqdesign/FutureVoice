// Every PostHog query the console makes goes through here (2026-11-20).
//
// "PostHog을 읽지 못했어요 (posthog 429)" had become a daily sight on the live
// tab. PostHog rate-limits its query API per PROJECT, and caps how many
// queries a project may run at once; the console was spending both freely:
// a page load fired ~8 HogQL queries side by side, the live tab asked twice a
// minute (presence + the trial/podcast events) and the web map three times a
// minute, each held only in its own isolate's memory, so a second tab or a
// fresh isolate asked again. Dear RoRo's page reads the same project.
//
// Three things here:
//   * results are held in the Cloudflare cache, shared by every isolate in
//     the colo, for a TTL the caller picks (a city doesn't move in a minute);
//   * at most MAX_IN_FLIGHT queries run at once per isolate, the rest wait;
//   * a 429 opens a cooldown during which nothing is sent and the last good
//     answer (kept a day) is served, so a limit isn't hammered back into.
// The database half of the console is never cached; only PostHog is.

export interface PostHogEnv {
  POSTHOG_API_KEY?: string;
  POSTHOG_PROJECT_ID?: string;
}

const MAX_IN_FLIGHT = 2;
const COOLDOWN_MS = 90_000;
const STALE_SECONDS = 86_400;

let inFlight = 0;
const waiting: Array<() => void> = [];
let cooldownUntil = 0;
const memo = new Map<string, { at: number; rows: unknown[][] }>();

async function slot<T>(fn: () => Promise<T>): Promise<T> {
  if (inFlight >= MAX_IN_FLIGHT) await new Promise<void>((r) => waiting.push(r));
  inFlight++;
  try {
    return await fn();
  } finally {
    inFlight--;
    waiting.shift()?.();
  }
}

async function keyFor(project: string, query: string, kind: "fresh" | "stale"): Promise<Request> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(project + "\n" + query));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return new Request(`https://posthog-cache.internal/${kind}/${hex}`);
}

function cache(): Cache | null {
  try { return (globalThis as any).caches?.default ?? null; } catch { return null; }
}

async function cached(key: Request): Promise<unknown[][] | null> {
  const c = cache();
  if (!c) return null;
  try {
    const r = await c.match(key);
    return r ? await r.json() as unknown[][] : null;
  } catch { return null; }
}

async function store(key: Request, rows: unknown[][], seconds: number): Promise<void> {
  const c = cache();
  if (!c) return;
  try {
    await c.put(key, new Response(JSON.stringify(rows), {
      headers: { "Content-Type": "application/json", "Cache-Control": `max-age=${seconds}` },
    }));
  } catch { /* the cache is a saving, never a requirement */ }
}

/** One HogQL query, its rows. `ttlSeconds` is how old an answer may be. */
export async function hogqlCached(env: PostHogEnv, query: string, ttlSeconds: number): Promise<unknown[][]> {
  if (!env.POSTHOG_API_KEY) throw new Error("no_key");
  const project = env.POSTHOG_PROJECT_ID || "@current";
  const id = project + "\n" + query;

  const m = memo.get(id);
  if (m && Date.now() - m.at < ttlSeconds * 1000) return m.rows;
  const freshKey = await keyFor(project, query, "fresh");
  const hit = await cached(freshKey);
  if (hit) {
    memo.set(id, { at: Date.now(), rows: hit });
    return hit;
  }

  const stale = async (why: string) => {
    const old = m?.rows ?? await cached(await keyFor(project, query, "stale"));
    if (old) return old;
    throw new Error(why);
  };
  if (Date.now() < cooldownUntil) return stale("posthog 429");

  return slot(async () => {
    // Another waiter may have filled it while this one queued.
    const again = await cached(freshKey);
    if (again) return again;
    if (Date.now() < cooldownUntil) return stale("posthog 429");
    const r = await fetch(`https://eu.posthog.com/api/projects/${project}/query/`, {
      method: "POST",
      headers: { Authorization: `Bearer ${env.POSTHOG_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query: { kind: "HogQLQuery", query } }),
    });
    if (!r.ok) {
      if (r.status === 429) {
        const after = Number(r.headers.get("Retry-After"));
        cooldownUntil = Date.now() + (after > 0 ? Math.min(after * 1000, 600_000) : COOLDOWN_MS);
        console.log(`posthog 429: ${(await r.text()).slice(0, 200)}`);
      }
      return stale(`posthog ${r.status}`);
    }
    const rows = ((await r.json()) as { results?: unknown[][] }).results ?? [];
    memo.set(id, { at: Date.now(), rows });
    if (memo.size > 200) memo.delete(memo.keys().next().value!);
    await Promise.all([
      store(freshKey, rows, ttlSeconds),
      store(await keyFor(project, query, "stale"), rows, STALE_SECONDS),
    ]);
    return rows;
  });
}
