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

export interface Env {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  ADMIN_TOKEN: string;
  ADMIN_PASSWORD?: string;
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
  return assemble(await r.json());
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
:root{color-scheme:light dark;--page:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink-2:#52514e;--muted:#898781;
  --ring:rgba(11,11,11,.12);--s1:#2a78d6;--crit:#d03b3b}
@media (prefers-color-scheme:dark){:root{--page:#0d0d0d;--surface:#1a1a19;--ink:#fff;--ink-2:#c3c2b7;--muted:#898781;--ring:rgba(255,255,255,.12);--s1:#3987e5;--crit:#e66767}}
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
      if (path === "/data.json") return text("Not found", 404);
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
      .replace("__ADMIN_BASE__", base);
    return html(page);
  },
};
