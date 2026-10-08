// What does the fluent self SAY to a line the learner said in their native
// language? (2026-10-08) Runs the app's live A2 prompt (dumped by
// ConversationPromptDumpTests into /tmp/fv-prompt-dump) with the realtime
// style rules, the gateway's reply settings, and a Korean learner turn —
// raw, as the gateway forwarded it before, and wrapped by `nativeTurnText`
// (src/session.ts). Counts in code: replies with Hangul in them, and
// replies that carry an English rendering (a quoted or "you mean" line).
//   node test/probe-native-reply.mjs [runs=3] [model]
import { readFileSync } from "node:fs"
const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const KEY = vars.match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)[1]
const runs = Number(process.argv[2] ?? 3)
const model = process.argv[3] ?? "gemini-3.6-flash"
const level = process.env.LEVEL ?? "a2"
const target = process.env.TARGET ?? "en"
const system = readFileSync(`/tmp/fv-prompt-dump/${target}-${level}.txt`, "utf8") + readFileSync("/tmp/claude-502/style.txt", "utf8")
const { nativeTurnText } = await import("../src/native-turn.ts")

const CASES = [
  ["So, how's work been this week?", "회사에서 회의가 너무 많아서 피곤해."],
  ["What do you do to relax on weekends?", "나는 즐기기로 마음 먹었기 때문에 재밌을 때까지만 할 거야."],
  ["What kind of bag are you looking for?", "가벼운"],
  ["What's your plan for today?", "일단"],
  ["Did you finish the book?", "잘 모르겠어. 너무 어려워."],
  ["Why do you want to learn English?", "I want to... 그걸 영어로 뭐라고 하지? 승진"],
]

async function reply(history) {
  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ systemInstruction: { parts: [{ text: system }] },
      contents: history.map((t) => ({ role: t.role, parts: [{ text: t.text }] })),
      generationConfig: { maxOutputTokens: 1024, thinkingConfig: { thinkingLevel: "minimal" } } }) })
  const j = await res.json()
  return (j.candidates?.[0]?.content?.parts ?? []).filter((p) => !p.thought).map((p) => p.text).join("").trim() || `ERR ${res.status}`
}

const tally = { raw: { hangul: 0, n: 0 }, wrapped: { hangul: 0, n: 0 } }
for (const [q, said] of CASES) {
  for (const mode of ["raw", "wrapped"]) {
    for (let r = 0; r < runs; r++) {
      const text = mode === "raw" ? said : nativeTurnText(said, { en: "English", de: "German" }[target], "Korean")
      const out = await reply([{ role: "model", text: q }, { role: "user", text }])
      tally[mode].n += 1
      if (/[가-힣]/.test(out)) tally[mode].hangul += 1
      console.log(`[${mode}] ${said}\n   → ${out}`)
    }
  }
}
console.log(`\n${model} ${target}-${level}: raw ${tally.raw.hangul}/${tally.raw.n} replies with Hangul · wrapped ${tally.wrapped.hangul}/${tally.wrapped.n}`)
