// Does an explicit cachedContent work for the reply call, what does it bill,
// and does it move time-to-first-text? (2026-10-08) Runs the dumped live
// prompt (/tmp/fv-prompt-dump, ConversationPromptDumpTests) both ways.
//   node test/probe-reply-cache.mjs [runs=4] [model]
import { readFileSync } from "node:fs"
const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const KEY = vars.match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)[1]
const runs = Number(process.argv[2] ?? 4)
const model = process.argv[3] ?? "gemini-3.6-flash"
const system = readFileSync(`/tmp/fv-prompt-dump/${process.env.TARGET ?? "en"}-${process.env.LEVEL ?? "a2"}.txt`, "utf8")
const API = "https://generativelanguage.googleapis.com/v1beta"
const gen = { maxOutputTokens: 1024, thinkingConfig: { thinkingLevel: "minimal" } }

const c = await fetch(`${API}/cachedContents?key=${KEY}`, { method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ model: `models/${model}`, systemInstruction: { parts: [{ text: system }] }, ttl: "300s" }) })
const cache = await c.json()
console.log("create", c.status, cache.name, JSON.stringify(cache.usageMetadata ?? cache.error))

async function once(useCache, history) {
  const t0 = Date.now()
  const body = useCache ? { cachedContent: cache.name } : { systemInstruction: { parts: [{ text: system }] } }
  const res = await fetch(`${API}/models/${model}:streamGenerateContent?alt=sse&key=${KEY}`, { method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...body, contents: history.map((t) => ({ role: t.role, parts: [{ text: t.text }] })), generationConfig: gen }) })
  if (!res.ok) return { err: `${res.status} ${(await res.text()).slice(0, 200)}` }
  const text = await res.text(); let first = null, usage = null, out = ""
  for (const l of text.split("\n")) { if (!l.startsWith("data:")) continue; const j = JSON.parse(l.slice(5))
    for (const p of j.candidates?.[0]?.content?.parts ?? []) if (p.text) out += p.text
    if (j.usageMetadata) usage = j.usageMetadata }
  return { ms: Date.now() - t0, usage, out: out.trim().slice(0, 80) }
}
const H = [{ role: "model", text: "Hey! So, how's work been this week?" }, { role: "user", text: "It was busy, many meetings. I am tired." }]
for (let r = 0; r < runs; r++) for (const u of [false, true]) {
  const x = await once(u, H)
  console.log(u ? "cached  " : "uncached", x.err ?? `${x.ms}ms in=${x.usage?.promptTokenCount} cached=${x.usage?.cachedContentTokenCount ?? 0} out=${x.usage?.candidatesTokenCount} th=${x.usage?.thoughtsTokenCount ?? 0} | ${x.out}`)
}
await fetch(`${API}/${cache.name}?key=${KEY}`, { method: "DELETE" })
