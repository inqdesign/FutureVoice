// 라이브 지도 · 웹: /admin/visitors/data.json (2026-11-12), drawn by the 앱 / 웹 switch on the live map.
//
// The web pages' visits on a map, the way the 라이브 지도 shows the app's
// people: where each visit came from, whether it is on the page right now,
// how far down it got and whether it reached the form. Read from PostHog only
// (GeoIP city on every event is PostHog's default), behind the console's
// session like every other byte here.
//
// One VISIT is one distinct_id on one page. The creators page runs PostHog in
// memory (no cookie, no stored id), so there every page load is its own id and
// a visit is exactly a page load; a returning reader is a new visit. The
// team's own browsers never start PostHog (the "nawana-internal" mark), and
// local previews are another host, so neither is here.

import { hogqlCached } from "./posthog";

export interface VisitorsEnv {
  POSTHOG_API_KEY?: string;
  POSTHOG_PROJECT_ID?: string;
}

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, private",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

/** Path → the page's short name. Anything else keeps its path. */
const PAGE_SQL = `multiIf(
  properties.$pathname in ('/creators', '/creators/', '/creators.html'), 'creators',
  properties.$pathname in ('/pay', '/creators-pay.html'), 'pay',
  properties.$pathname in ('/', '/index.html'), 'home',
  properties.$pathname in ('/ko', '/ko.html'), 'ko',
  properties.$pathname in ('/community', '/community/', '/community.html'), 'community',
  coalesce(properties.$pathname, '?'))`;

/** The events that are a reader leaving, not a reader doing something. */
const LEAVE = ["creators_leave", "$pageleave"];

export async function visitorsData(env: VisitorsEnv, url: URL): Promise<Response> {
  if (!env.POSTHOG_API_KEY) return json({ error: "no_key" }, 503);
  const days = url.searchParams.get("days") === "7" ? 7 : 1;
  const query = `
    select distinct_id,
      ${PAGE_SQL} as page,
      min(timestamp), max(timestamp),
      argMax(event, timestamp) as last_event,
      any(properties.$geoip_city_name), any(properties.$geoip_country_code),
      any(properties.$geoip_latitude), any(properties.$geoip_longitude),
      any(properties.$device_type), any(properties.$os), any(properties.$browser),
      any(properties.$referring_domain),
      anyIf(properties.ref, properties.ref != ''),
      max(toInt(properties.n)) as deepest,
      argMax(properties.section, toInt(properties.n)),
      countIf(event = 'creators_form_started'),
      countIf(event = 'creators_applied'),
      countIf(event = 'creators_sample_play'),
      countIf(event = 'creators_cta'),
      max(toInt(properties.seconds)),
      max(toInt(properties.scroll)),
      count()
    from events
    where timestamp > now() - interval ${days} day
      and properties.$host in ('nawana.app', 'www.nawana.app')
      and event != '$web_vitals'
    group by distinct_id, page
    order by max(timestamp) desc
    limit 3000`;
  let rows: unknown[][];
  try {
    // The map polls every 20 s; one answer a minute is shared (posthog.ts).
    rows = await hogqlCached(env, query, 60);
  } catch (e) {
    return json({ error: (e as Error).message }, 502);
  }
  // PostHog's timestamps come back without a zone; they are UTC.
  const iso = (v: unknown) => {
    const s = String(v ?? "");
    return new Date(s.replace(" ", "T") + (/Z|[+-]\d\d:?\d\d$/.test(s) ? "" : "Z")).toISOString();
  };
  const num = (v: unknown) => (v === null || v === undefined || v === "" ? null : Number(v));
  const str = (v: unknown) => (v === null || v === undefined || v === "" ? null : String(v));
  const visits = rows.map((x) => ({
    // Only a short tail of the id: it names nobody, it just keeps pins apart.
    id: String(x[0] ?? "").slice(-10) + ":" + String(x[1]),
    page: String(x[1]),
    first: iso(x[2]),
    last: iso(x[3]),
    left: LEAVE.includes(String(x[4])),
    city: str(x[5]), cc: str(x[6]),
    lat: num(x[7]), lon: num(x[8]),
    device: str(x[9]), os: str(x[10]), browser: str(x[11]),
    from: str(x[12]), ref: str(x[13]),
    deepest: num(x[14]), deepestName: str(x[15]),
    started: Number(x[16]) > 0, applied: Number(x[17]) > 0,
    samples: Number(x[18]) || 0, ctas: Number(x[19]) || 0,
    seconds: num(x[20]), scroll: num(x[21]),
    events: Number(x[22]) || 0,
  }));
  return json({ now: new Date().toISOString(), days, visits });
}
