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
import { existsSync } from "node:fs"
// The live prompt when ConversationPromptDumpTests has dumped it; otherwise a
// stand-in long enough to cache (the API's minimum is ~1k tokens).
const dumped = "/tmp/fv-prompt-dump/en-a2.txt"
const system = existsSync(dumped) ? readFileSync(dumped, "utf8")
  : "You are the learner's fluent future self on a phone call, speaking English at A2. Reply in at most three short spoken sentences, react to what they said, then ask one simple concrete question.\n\n"
    + Array.from({ length: 120 }, (_, i) => `Rule ${i + 1}: keep the conversation natural and friendly, use everyday A2 words, never lecture, never correct grammar out loud, and follow what the learner actually said rather than a script.`).join("\n")
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
  check("6 broken primary → fallback answers", a.length > 0 && fell !== "", `${fell} | cacheOff=${e.cacheOff}`)
  e.dispose()
}

// 7. A prompt too short to cache: refused once, never asked again, answers.
{
  const e = new ReplyEngine({ apiKey, model: "gemini-3.6-flash", fallbackModel: "gemini-3.1-flash-lite", system: "You are a friendly English tutor. Reply in one short sentence." })
  const a = await gen(e); await wait(2000); const b = await gen(e)
  check("7 short prompt → uncached, answers", a.length > 0 && b.length > 0 && e.cacheOff === true, `cacheOff=${e.cacheOff}`)
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
// 9. The call so far rides in the cache (2026-10-20): a long history makes a
//    cache holding its settled prefix, the next generation sends only the
//    tail, a reopened last turn still fits, and a changed early line falls
//    back to the whole history uncached and still answers.
{
  const lines = ["How was your weekend?", "I stayed home. I was very tired.", "Oh no, why were you so tired?",
    "I worked a lot this week.", "What do you do for work?", "I am a nurse in a hospital.",
    "That sounds hard. Do you work at night?", "Sometimes. This week I worked three nights.",
    "Three nights is a lot. How do you sleep in the day?", "I use a mask and earplugs.",
    "Smart. Does it work well?", "Mostly yes, but my neighbours are loud.", "Ugh. What do they do?",
    "They have a dog. It barks every afternoon."]
  const h = lines.map((text, i) => ({ role: i % 2 === 0 ? "model" : "user", text }))
  // No hedge here: a slow primary would let the uncached fallback answer and
  // its tokens would read as the cache missing.
  const e = new ReplyEngine({ apiKey, model: "gemini-3.6-flash", system })
  await gen(e, h); await wait(3000)
  check("9a prefix cached", e.cache && e.cache.prefix.length === 11, `prefix=${e.cache?.prefix.length}`)
  const before = { ...e.usage }
  const a = await gen(e, h)
  const uncached = (e.usage.promptTokens - before.promptTokens) - (e.usage.cachedTokens - before.cachedTokens)
  check("9b only the tail is sent", a.length > 0 && uncached < 150, `uncached=${uncached} cached=${e.usage.cachedTokens - before.cachedTokens}`)
  const reopened = [...h.slice(0, 13), { role: "user", text: "They have a dog and it barks every afternoon, so I wake up." }]
  const name = e.cache.name
  const b = await gen(e, reopened)
  check("9c reopened turn still fits", b.length > 0 && e.cache.name === name, `"${b.slice(0, 50)}"`)
  const changed = h.map((t, i) => i === 3 ? { ...t, text: "I worked a lot." } : t)
  // (Gemini's own implicit cache may still count some of it as cached.)
  const c = await gen(e, changed); await wait(3000)
  check("9d changed early line → whole history, answers, new cache", c.length > 0
    && e.cache.name !== name && e.cache.prefix[3].text === "I worked a lot.", `"${c.slice(0, 50)}"`)
  const grown = [...h, { role: "model", text: "A dog every afternoon is hard. Did you talk to them?" },
    { role: "user", text: "Not yet. I am a bit shy." }, { role: "model", text: "I get that. What would you say?" },
    { role: "user", text: "Maybe I say please keep the dog inside." }, { role: "model", text: "That is polite and clear." },
    { role: "user", text: "Thanks, I will try tomorrow." }, { role: "model", text: "Good luck! Tell me how it goes." },
    { role: "user", text: "OK. And you, did you sleep well?" }]
  const prev = e.cache.prefix.length
  await gen(e, grown); await wait(3000)
  check("9e outgrown cache rebuilt longer", e.cache.prefix.length > prev, `${prev} → ${e.cache.prefix.length}`)
  e.dispose()
}
console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`)
process.exit(failures ? 1 : 0)
