// The reply cache's failure paths, against the real API (2026-10-08). A
// normal call only ever takes the happy path; these are the ones that must
// still answer the turn. Run: node test/reply-engine-check.mjs (Node 22;
// bundles src/reply.ts with the esbuild wrangler ships).
import { readFileSync } from "node:fs"
import { execFileSync } from "node:child_process"
const out = new URL("../.reply-check.mjs", import.meta.url).pathname
execFileSync(new URL("../node_modules/.bin/esbuild", import.meta.url).pathname,
  [new URL("../src/reply.ts", import.meta.url).pathname, "--bundle", "--format=esm", `--outfile=${out}`, "--log-level=warning"])
const { ReplyEngine } = await import(out)
const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const apiKey = vars.match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)[1]
const API = "https://generativelanguage.googleapis.com/v1beta"
const system = readFileSync("/tmp/fv-prompt-dump/en-a2.txt", "utf8")
const H = [{ role: "model", text: "How was your weekend?" }, { role: "user", text: "I stayed home. I was very tired." }]
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
let failures = 0
const check = (name, ok, detail = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${name} ${detail}`); if (!ok) failures++ }
const gen = (e, h = H, signal = new AbortController().signal) => e.generate(h, signal, () => {})
const getCache = (name) => fetch(`${API}/${name}?key=${apiKey}`).then(async (r) => ({ status: r.status, body: await r.json().catch(() => null) }))

// 1. First generation runs uncached and makes the cache; the second reads it.
{
  const e = new ReplyEngine({ apiKey, model: "gemini-3.6-flash", fallbackModel: "gemini-3.1-flash-lite", system })
  const a = await gen(e); await wait(2500)
  const b = await gen(e)
  check("1 cached after first", a && b && e.usage.cachedTokens > 3000, `cached=${e.usage.cachedTokens} prompt=${e.usage.promptTokens}`)

  // 2. Cache deleted behind its back: the turn still answers, uncached, and
  //    the next generation makes a new cache.
  const name = e.cache.name
  await fetch(`${API}/${name}?key=${apiKey}`, { method: "DELETE" })
  const before = e.usage.cachedTokens
  const c = await gen(e)
  check("2a answers after cache vanished", c.length > 0, `"${c.slice(0, 50)}"`)
  await wait(2500)
  const d = await gen(e)
  check("2b new cache made", e.cache && e.cache.name !== name && e.usage.cachedTokens > before, `cached=${e.usage.cachedTokens}`)

  // 3. Near expiry: the next generation stretches the TTL on the server.
  const t0 = new Date((await getCache(e.cache.name)).body.expireTime).getTime()
  e.cache.expiresAt = Date.now() + 1000            // pretend it is about to run out
  await gen(e); await wait(1500)
  const t1 = new Date((await getCache(e.cache.name)).body.expireTime).getTime()
  check("3 TTL stretched", t1 > t0, `+${Math.round((t1 - t0) / 1000)}s`)

  // 4. Steer rides on the turn: generation still works with a cached prompt.
  e.steer = "COACH MODE. The learner is studying: \"exhausted\". If it fits, you may end with a question whose natural answer uses it."
  const s = await gen(e)
  check("4 steer with cache", s.length > 0 && e.cache !== null, `"${s.slice(0, 70)}"`)

  // 5. Dispose deletes the cache.
  const last = e.cache.name
  e.dispose(); await wait(1500)
  check("5 disposed cache deleted", (await getCache(last)).status === 404 || (await getCache(last)).status === 403, `status=${(await getCache(last)).status}`)
}

// 6. Primary model broken: the hedge answers uncached, the call goes on.
{
  const e = new ReplyEngine({ apiKey, model: "gemini-does-not-exist", fallbackModel: "gemini-3.1-flash-lite", system })
  let fell = ""; e.onFallback = (d) => { fell = d }
  const a = await gen(e); await wait(2000)
  check("6 broken primary → fallback answers", a.length > 0 && fell !== "", `${fell} | cache=${e.cacheState}`)
  e.dispose()
}

// 7. A prompt too short to cache: refused once, never asked again, answers.
{
  const e = new ReplyEngine({ apiKey, model: "gemini-3.6-flash", fallbackModel: "gemini-3.1-flash-lite", system: "You are a friendly English tutor. Reply in one short sentence." })
  const a = await gen(e); await wait(2000); const b = await gen(e)
  check("7 short prompt → uncached, answers", a.length > 0 && b.length > 0 && e.cacheState === "off", `state=${e.cacheState}`)
  e.dispose()
}

// 8. Abort mid-stream (barge-in) on a cached generation.
{
  const e = new ReplyEngine({ apiKey, model: "gemini-3.6-flash", fallbackModel: "gemini-3.1-flash-lite", system })
  await gen(e); await wait(2500)
  const ac = new AbortController()
  const p = e.generate(H, ac.signal, () => ac.abort())
  const r = await p.catch((x) => `THREW ${x}`)
  check("8 abort resolves, doesn't throw", !String(r).startsWith("THREW"), `"${String(r).slice(0, 40)}"`)
  e.dispose()
}
console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`)
process.exit(failures ? 1 : 0)
