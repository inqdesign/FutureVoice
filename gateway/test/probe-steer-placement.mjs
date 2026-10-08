// Coach mode's steer: in the system instruction (today) vs as a note on the
// learner's last turn (what an explicitly cached system prompt forces).
// (2026-10-08) A flash-lite judge says, per reply, whether its question
// invites an answer using the studied item; code counts replies that say
// the item themselves (forbidden). Same live A2 prompt as the other probes.
//   node test/probe-steer-placement.mjs [runs=3]
import { readFileSync } from "node:fs"
const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const KEY = vars.match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)[1]
const runs = Number(process.argv[2] ?? 3)
const system = readFileSync("/tmp/fv-prompt-dump/en-a2.txt", "utf8")
const { steerTurnText } = await import("../src/steer-turn.ts")
const API = "https://generativelanguage.googleapis.com/v1beta"
const steerFor = (items) => `COACH MODE. The learner is studying: ${items.map((i) => `"${i}"`).join(", ")}. If — and only if — one of them fits what you are ALREADY talking about, you may end this reply with a question whose most natural answer would use it. Do not say that word yourself, do not mention practice, words or coaching, and never steer the topic toward a word. Most replies should simply continue the conversation as they would have.`

// [fluent self's last line, learner's answer, studied items, the item that fits or null]
const CASES = [
  ["What did you do last weekend?", "I stayed home. I was very tired.", ["exhausted", "commute", "budget"], "exhausted"],
  ["How do you get to work?", "I take the bus. It takes one hour.", ["commute", "recipe", "allergic"], "commute"],
  ["What did you eat for dinner?", "I cooked pasta with my wife.", ["recipe", "deadline", "landlord"], "recipe"],
  ["Are you going anywhere this summer?", "Maybe Spain. But it is expensive.", ["budget", "allergic", "promotion"], "budget"],
  ["What's your favourite movie?", "I like Studio Ghibli movies.", ["landlord", "deadline", "mortgage"], null],
  ["How's your new apartment?", "It's nice but small.", ["photosynthesis", "deadline", "allergic"], null],
]

async function call(body, model = "gemini-3.6-flash") {
  const r = await fetch(`${API}/models/${model}:generateContent?key=${KEY}`, { method: "POST",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
  const j = await r.json()
  return (j.candidates?.[0]?.content?.parts ?? []).filter((p) => !p.thought).map((p) => p.text).join("").trim() || `ERR ${r.status} ${JSON.stringify(j).slice(0,200)}`
}
const gen = { maxOutputTokens: 1024, thinkingConfig: { thinkingLevel: "minimal" } }
async function judge(reply, item) {
  const out = await call({ contents: [{ role: "user", parts: [{ text:
    `A tutor said: "${reply}"\nWould the most natural answer to its LAST question use the word or phrase "${item}"? Answer only yes or no.` }] }],
    generationConfig: { maxOutputTokens: 20, thinkingConfig: { thinkingLevel: "minimal" } } }, "gemini-3.1-flash-lite")
  return /^yes/i.test(out)
}
const tally = {}
for (const mode of ["system", "turn"]) tally[mode] = { fitAsked: 0, fitN: 0, saidIt: 0, noFitSteered: 0, noFitN: 0, n: 0 }
for (const [q, said, items, fits] of CASES) for (const mode of ["system", "turn"]) for (let r = 0; r < runs; r++) {
  const steer = steerFor(items)
  const body = mode === "system"
    ? { systemInstruction: { parts: [{ text: `${system}\n\n${steer}` }] }, contents: [{ role: "model", parts: [{ text: q }] }, { role: "user", parts: [{ text: said }] }], generationConfig: gen }
    : { systemInstruction: { parts: [{ text: system }] }, contents: [{ role: "model", parts: [{ text: q }] }, { role: "user", parts: [{ text: steerTurnText(said, steer) }] }], generationConfig: gen }
  const out = await call(body)
  const t = tally[mode]; t.n++
  if (items.some((i) => out.toLowerCase().includes(i))) t.saidIt++
  if (fits) { t.fitN++; if (await judge(out, fits)) t.fitAsked++ }
  else { t.noFitN++; if (await Promise.all(items.map((i) => judge(out, i))).then((a) => a.some(Boolean))) t.noFitSteered++ }
  console.log(`[${mode}] ${said} → ${out}`)
}
for (const [m, t] of Object.entries(tally))
  console.log(`${m}: fit asked ${t.fitAsked}/${t.fitN} · forced when none fits ${t.noFitSteered}/${t.noFitN} · said the word ${t.saidIt}/${t.n}`)
