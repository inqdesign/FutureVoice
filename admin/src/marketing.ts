// The 마케팅 tab's server half (marketing/AUTOMATION.md §4 and §7).
//
// Two very different doors live here, on purpose side by side:
//
//   * /media/<key> — PUBLIC. The carousel files in R2 (`MEDIA`, bucket
//     `nawana-marketing`), fetched by Instagram's and Threads' servers when the
//     scheduler hands them a URL, and by the community page. No cookie, no
//     token: what is in that bucket is material we are about to post to the
//     world. Keys are `<slug>/<file>` and are never edited in place, so the
//     cache is an hour (a re-rendered slide reuses its key); Range is answered because a video is
//     fetched in pieces.
//   * /marketing.json and the three POSTs — behind the session like every
//     other byte of the console. The tables are RLS-locked with no policies,
//     so they are read and written with the service-role key, which never
//     leaves the Worker.
//
// The tables arrive with migration 20261011121500_marketing.sql. A Worker
// deployed ahead of it answers `missing: true` and the tab shows its empty
// state rather than an error.

export interface MarketingEnv {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  MEDIA?: R2Bucket;
}

// ---------------------------------------------------------------- media

const TYPES: Record<string, string> = {
  mp4: "video/mp4", mov: "video/quicktime", webm: "video/webm", m4v: "video/mp4",
  jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif",
  json: "application/json", txt: "text/plain; charset=utf-8",
};

function typeOf(key: string, stored?: string): string {
  if (stored && stored !== "application/octet-stream") return stored;
  const ext = key.split(".").pop()?.toLowerCase() ?? "";
  return TYPES[ext] ?? "application/octet-stream";
}

const notFound = () => new Response("Not found", {
  status: 404,
  headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
});

/** `rest` is everything after `/media/`, still URL-encoded. */
export async function serveMedia(req: Request, env: MarketingEnv, rest: string): Promise<Response> {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  if (!env.MEDIA) return notFound();
  let key: string;
  try { key = decodeURIComponent(rest); } catch { return notFound(); }
  // Keys are `<slug>/<file>`. Nothing else is ever in the bucket, and a
  // path that climbs or is empty is never one of them.
  if (!key || key.length > 512 || key.startsWith("/") || key.split("/").some((p) => !p || p === "." || p === "..")) {
    return notFound();
  }

  const wantsRange = req.headers.has("Range");
  const obj = req.method === "HEAD"
    ? await env.MEDIA.head(key)
    : await env.MEDIA.get(key, { range: req.headers });
  if (!obj) return notFound();

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set("Content-Type", typeOf(key, obj.httpMetadata?.contentType));
  headers.set("Cache-Control", "public, max-age=3600");
  headers.set("ETag", obj.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Access-Control-Allow-Origin", "*");

  const size = obj.size;
  const body = "body" in obj ? (obj as R2ObjectBody).body : null;
  const r = obj.range as { offset?: number; length?: number; suffix?: number } | undefined;
  if (wantsRange && r && body) {
    let start: number, len: number;
    if (r.suffix != null) { len = Math.min(r.suffix, size); start = size - len; }
    else { start = r.offset ?? 0; len = r.length ?? size - start; }
    if (start >= size || len <= 0) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${size}` } });
    }
    headers.set("Content-Range", `bytes ${start}-${start + len - 1}/${size}`);
    headers.set("Content-Length", String(len));
    return new Response(body, { status: 206, headers });
  }
  headers.set("Content-Length", String(size));
  return new Response(body, { status: 200, headers });
}

// ---------------------------------------------------------------- reads

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, private",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

class Missing extends Error {}

async function rest(env: MarketingEnv, path: string, init: RequestInit = {}): Promise<any> {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers as Record<string, string> | undefined),
    },
  });
  if (!r.ok) {
    const t = await r.text();
    // The table isn't there yet (the Worker went out ahead of the migration).
    if (r.status === 404 || /PGRST205|42P01|does not exist|Could not find the table/.test(t)) throw new Missing(t);
    throw new Error(`${path.split("?")[0]} ${r.status}: ${t.slice(0, 200)}`);
  }
  const t = await r.text();
  return t ? JSON.parse(t) : null;
}

type Slide = { n?: number; kind?: string; mp4?: string; png?: string; jpg?: string; jpg_web?: string; alt_ko?: string; alt_en?: string };
type Metric = { piece_id: string; channel: string; captured_at: string;
  views: number | null; reach: number | null; likes: number | null; comments: number | null;
  saves: number | null; shares: number | null };
const KEYS = ["views", "reach", "likes", "comments", "saves", "shares"] as const;
const CHART_KEYS = ["views", "reach", "likes", "saves"] as const;

/** A slide's file as a URL on whatever host the console was reached through.
 *  Keys are `<slug>/<file>`; a bare file name is read as this piece's. */
function mediaUrl(base: string, slug: string, key?: string): string | null {
  if (!key) return null;
  if (/^https:\/\//.test(key)) return key;
  const full = key.includes("/") ? key : `${slug}/${key}`;
  return `${base}/media/${full.split("/").map(encodeURIComponent).join("/")}`;
}

const dayOf = (iso: string) => iso.slice(0, 10);   // UTC day, like every DAY bucket on the page

export async function marketingData(env: MarketingEnv, base: string): Promise<Response> {
  try {
    const pieces = await rest(env,
      "marketing_pieces?select=*&order=created_at.desc&limit=60") as Array<Record<string, any>>;
    const now = new Date();
    const days: string[] = [];
    for (let i = 29; i >= 0; i--) days.push(new Date(now.getTime() - i * 86_400_000).toISOString().slice(0, 10));
    // Run-level events (run_start, run_end, metrics …) carry no piece.
    const runs = await rest(env, "marketing_events?select=at,kind,message&piece_id=is.null&order=at.desc&limit=30")
      .catch(() => []) as Array<Record<string, any>>;
    if (!pieces.length) return json({ pieces: [], days, totals: [], runs, now: now.toISOString() });

    const ids = pieces.map((p) => p.id).join(",");
    const [events, metrics] = await Promise.all([
      rest(env, `marketing_events?select=piece_id,at,kind,message&piece_id=in.(${ids})&order=at.desc&limit=3000`)
        .catch((e) => { if (e instanceof Missing) return []; throw e; }) as Promise<Array<Record<string, any>>>,
      rest(env, `marketing_metrics?select=piece_id,channel,captured_at,${KEYS.join(",")}`
        + `&piece_id=in.(${ids})&order=captured_at.asc&limit=20000`)
        .catch((e) => { if (e instanceof Missing) return []; throw e; }) as Promise<Metric[]>,
    ]);

    const evBy = new Map<string, Array<Record<string, any>>>();
    for (const e of events) {
      if (!e.piece_id) continue;
      const l = evBy.get(e.piece_id) ?? [];
      if (l.length < 20) l.push({ at: e.at, kind: e.kind, message: e.message });
      evBy.set(e.piece_id, l);
    }

    // Insights are LIFETIME counts, so a row is a snapshot: the latest per
    // (piece, channel) is what the post stands at, and a day's value is the
    // last snapshot on or before that day, carried forward.
    const latest = new Map<string, Record<string, Metric>>();
    const daily = new Map<string, Map<string, Map<string, Metric>>>();   // piece → channel → day → last row
    for (const m of metrics) {
      (latest.get(m.piece_id) ?? latest.set(m.piece_id, {}).get(m.piece_id)!)[m.channel] = m;
      const byCh = daily.get(m.piece_id) ?? daily.set(m.piece_id, new Map()).get(m.piece_id)!;
      const byDay = byCh.get(m.channel) ?? byCh.set(m.channel, new Map()).get(m.channel)!;
      byDay.set(dayOf(m.captured_at), m);
    }
    /** Per day: the sum across channels of each channel's standing that day. */
    const seriesOf = (pieceId: string) => {
      const byCh = daily.get(pieceId);
      if (!byCh) return [];
      const out = days.map((d) => ({ d, views: 0, reach: 0, likes: 0, saves: 0, any: false }));
      for (const byDay of byCh.values()) {
        const sorted = [...byDay.entries()].sort((a, b) => a[0].localeCompare(b[0]));
        let j = 0; let cur: Metric | null = null;
        for (const o of out) {
          while (j < sorted.length && sorted[j][0] <= o.d) cur = sorted[j++][1];
          if (!cur) continue;
          o.any = true;
          for (const k of CHART_KEYS) o[k] += Number(cur[k] ?? 0);
        }
      }
      return out;
    };

    const totals = days.map((d) => ({ d, views: 0, reach: 0, likes: 0, saves: 0 }));
    const shaped = pieces.map((p) => {
      const series = seriesOf(p.id);
      series.forEach((s, i) => { for (const k of CHART_KEYS) totals[i][k] += s[k]; });
      const lat = latest.get(p.id) ?? {};
      const slides = (Array.isArray(p.slides) ? p.slides as Slide[] : []).map((s, i) => ({
        n: s.n ?? i + 1,
        kind: s.kind === "video" || (!s.kind && s.mp4) ? "video" : "image",
        video: mediaUrl(base, p.slug, s.mp4),
        image: mediaUrl(base, p.slug, s.png ?? s.jpg ?? s.jpg_web),
        alt: s.alt_ko ?? s.alt_en ?? "",
      }));
      return {
        id: p.id, slug: p.slug, version: p.version, build: p.build, phase: p.phase, stage: p.stage,
        title_ko: p.title_ko, title_en: p.title_en, one_message: p.one_message,
        review_verdict: p.review_verdict, review_fixes: p.review_fixes,
        caption_ko: p.caption_ko, caption_en: p.caption_en, threads_text: p.threads_text,
        slides,
        scheduled_at: p.scheduled_at, vetoed_at: p.vetoed_at, veto_reason: p.veto_reason,
        posted_at: p.posted_at, ig_permalink: p.ig_permalink, threads_permalink: p.threads_permalink,
        community_news_id: p.community_news_id, show_in_community: p.show_in_community,
        error: p.error, created_at: p.created_at, updated_at: p.updated_at,
        events: evBy.get(p.id) ?? [],
        latest: Object.fromEntries(Object.entries(lat).map(([ch, m]) => [ch,
          { at: m.captured_at, ...Object.fromEntries(KEYS.map((k) => [k, m[k]])) }])),
        series: series.some((s) => s.any) ? series.map(({ any: _a, ...s }) => s) : [],
      };
    });
    return json({ pieces: shaped, days, totals, runs, now: now.toISOString() });
  } catch (e) {
    if (e instanceof Missing) return json({ pieces: [], days: [], totals: [], missing: true, now: new Date().toISOString() });
    return json({ error: (e as Error).message }, 502);
  }
}

// ---------------------------------------------------------------- actions

/** Where 지금 올리기 / 미루기 may take a piece from. */
export const RESCHEDULABLE = ["scheduled", "ready", "vetoed", "failed"];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The cookie is SameSite=Lax, so a cross-site form can't carry it; this is
 *  the second lock. A JSON body from another origin needs a preflight this
 *  Worker never answers, and a browser that says where the request came
 *  from must say it came from here. */
function sameOrigin(req: Request): boolean {
  if (!(req.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/json")) return false;
  const site = req.headers.get("Sec-Fetch-Site");
  if (site && site !== "same-origin") return false;
  const origin = req.headers.get("Origin");
  if (origin) {
    let host: string;
    try { host = new URL(origin).host; } catch { return false; }
    const self = new URL(req.url).host;
    if (host !== self && host !== "nawana.app" && host !== "www.nawana.app") return false;
  }
  return true;
}

async function patchWhere(env: MarketingEnv, id: string, stages: string[], body: Record<string, unknown>) {
  const rows = await rest(env,
    `marketing_pieces?id=eq.${id}&stage=in.(${stages.join(",")})&select=id,stage,scheduled_at`, {
      method: "PATCH",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify(body),
    }) as Array<Record<string, unknown>>;
  return rows?.[0] ?? null;
}

async function event(env: MarketingEnv, pieceId: string, kind: string, message: string) {
  await rest(env, "marketing_events", {
    method: "POST",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ piece_id: pieceId, kind, message }),
  });
}

/** `/marketing/<id>/<action>`; the caller has checked the session. */
export async function marketingAction(req: Request, env: MarketingEnv, id: string, action: string): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!sameOrigin(req)) return json({ error: "origin" }, 403);
  if (!UUID.test(id)) return json({ error: "bad_id" }, 400);
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const now = new Date();
  try {
    if (action === "veto") {
      const reason = String(body.reason ?? "").trim().slice(0, 500);
      if (!reason) return json({ error: "reason_required" }, 400);
      // Anything not yet on its way out can be stopped; once the scheduler
      // has picked it up (`posting`) or it is live, a veto says nothing.
      const row = await patchWhere(env, id,
        ["idea", "brief", "copy", "design", "review", "ready", "scheduled", "failed"],
        { stage: "vetoed", vetoed_at: now.toISOString(), veto_reason: reason });
      if (!row) return json({ error: "state_changed" }, 409);
      await event(env, id, "veto", `콘솔에서 막음: ${reason}`);
      return json({ ok: true, piece: row });
    }
    if (action === "post-now" || action === "reschedule") {
      let hours = 0;
      if (action === "reschedule") {
        hours = Number(body.hours);
        if (!Number.isFinite(hours) || hours <= 0 || hours > 24 * 14) return json({ error: "bad_hours" }, 400);
      }
      // The scheduler only picks up stage='scheduled', so both buttons put the
      // piece there — from ready, vetoed or failed too — and clear what kept
      // it out. Never a piece without a reviewer PASS (AUTOMATION.md §8): one
      // vetoed while still being made goes back through the team.
      const cur = await rest(env, `marketing_pieces?id=eq.${id}&select=stage,review_verdict`) as Array<Record<string, unknown>>;
      if (!cur?.length) return json({ error: "not_found" }, 404);
      const from = String(cur[0].stage);
      if (!RESCHEDULABLE.includes(from)) return json({ error: "state_changed" }, 409);
      if (!/^pass/i.test(String(cur[0].review_verdict ?? ""))) return json({ error: "not_reviewed" }, 409);
      const at = new Date(now.getTime() + hours * 3_600_000).toISOString();
      const row = await patchWhere(env, id, [from],
        { stage: "scheduled", scheduled_at: at, vetoed_at: null, veto_reason: null, error: null });
      if (!row) return json({ error: "state_changed" }, 409);
      const was = from === "scheduled" ? "" : `${from}에서 다시 `;
      await event(env, id, "scheduled", action === "post-now"
        ? `콘솔에서 ${was}지금 올리기 — 다음 스케줄러 실행에 올라가요`
        : `콘솔에서 ${was}${hours}시간 뒤로 예약 (${at})`);
      return json({ ok: true, piece: row });
    }
    return json({ error: "unknown_action" }, 404);
  } catch (e) {
    if (e instanceof Missing) return json({ error: "tables_missing" }, 503);
    return json({ error: (e as Error).message }, 502);
  }
}
