// The admin console, served live.
//
// Every load reads production: one RPC to admin_raw(), assembled here into the
// page's data blob and injected into the shell. There is nothing to rebuild
// and nothing to remember to republish — which is the whole reason this
// exists (2026-09-04: the static artifact was found showing 8/27 numbers with
// three signups missing, because the gather had run and the republish hadn't).
//
// The page holds real names, real addresses and people's self-intros, so:
//   * the service-role key never leaves the Worker — the browser gets HTML,
//     never a token and never a Supabase call of its own;
//   * an unauthenticated request gets a 404, not a 401 — a login page tells a
//     scanner there is something here;
//   * noindex and no-store, because a cached copy of this on a proxy is the
//     same leak as a shared link.

import shell from "./shell.html";
import { assemble } from "./assemble";

export interface Env {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  ADMIN_TOKEN: string;
}

const COOKIE = "nawana_admin";
// A page load runs one aggregate query over the whole ledger. Holding the
// result briefly means a reload — which is how you check a number twice — is
// free, while still being "just now" by any reading of the word. `?fresh=1`
// skips it.
const CACHE_MS = 60_000;

let cached: { at: number; data: unknown } | null = null;

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

async function fetchData(env: Env, fresh: boolean) {
  if (!fresh && cached && Date.now() - cached.at < CACHE_MS) return cached.data;
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
  const data = assemble(await r.json());
  cached = { at: Date.now(), data };
  return data;
}

const PRIVATE_HEADERS = {
  "Cache-Control": "no-store, private",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
};

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    const fromQuery = url.searchParams.get("k");
    const supplied = fromQuery ?? cookieValue(req.headers.get("Cookie"), COOKIE);
    if (!env.ADMIN_TOKEN || !supplied || !constantTimeEqual(supplied, env.ADMIN_TOKEN)) {
      return new Response("Not found", { status: 404, headers: PRIVATE_HEADERS });
    }

    if (!env.SUPABASE_SERVICE_ROLE_KEY) {
      return new Response(
        "SUPABASE_SERVICE_ROLE_KEY가 아직 없어요. (ADMIN_TOKEN은 설정돼 있어요 —\n" +
        "이 화면이 보인다는 게 그 증거예요.)\n\n" +
        "  bash admin/deploy.sh secret SUPABASE_SERVICE_ROLE_KEY\n\n" +
        "키는 Supabase 대시보드 → Project Settings → API keys → service_role.\n",
        { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8", ...PRIVATE_HEADERS } },
      );
    }

    // Arriving with ?k= puts the key in the address bar, in history and in
    // every screenshot. Trade it for a cookie once and redirect it away.
    if (fromQuery) {
      const clean = new URL(url);
      clean.searchParams.delete("k");
      return new Response(null, {
        status: 302,
        headers: {
          Location: clean.pathname + clean.search,
          "Set-Cookie":
            `${COOKIE}=${encodeURIComponent(fromQuery)}; HttpOnly; Secure; ` +
            `SameSite=Lax; Path=/; Max-Age=${60 * 60 * 24 * 180}`,
          ...PRIVATE_HEADERS,
        },
      });
    }

    const fresh = url.searchParams.get("fresh") === "1";
    let data: unknown;
    try {
      data = await fetchData(env, fresh);
    } catch (e) {
      return new Response(`데이터를 읽지 못했어요\n\n${(e as Error).message}\n`, {
        status: 502,
        headers: { "Content-Type": "text/plain; charset=utf-8", ...PRIVATE_HEADERS },
      });
    }

    if (url.pathname === "/data.json") {
      return new Response(JSON.stringify(data), {
        headers: { "Content-Type": "application/json; charset=utf-8", ...PRIVATE_HEADERS },
      });
    }

    const html = (shell as unknown as string).replace(
      "__ADMIN_DATA__", () => JSON.stringify(data));
    return new Response(html, {
      headers: { "Content-Type": "text/html; charset=utf-8", ...PRIVATE_HEADERS },
    });
  },
};
