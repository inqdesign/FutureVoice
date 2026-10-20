// The Claude reply path (claude-reply.ts) against the real APIs (2026-10-21).
// Run: node test/claude-reply-check.mjs (Node 22). Reads GEMINI_API_KEY from
// .dev.vars and the Anthropic key from ANTHROPIC_API_KEY or ~/keys/anthropic.txt.
import { readFileSync, existsSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { homedir } from "node:os"
const out = new URL("../.claude-check.mjs", import.meta.url).pathname
execFileSync(new URL("../node_modules/.bin/esbuild", import.meta.url).pathname,
  [new URL("../src/reply.ts", import.meta.url).pathname, "--bundle", "--format=esm", `--outfile=${out}`, "--log-level=warning"])
const { ReplyEngine } = await import(out)
const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const apiKey = vars.match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)[1]
const anthropicKey = process.env.ANTHROPIC_API_KEY ?? readFileSync(`${homedir()}/keys/anthropic.txt`, "utf8").trim()
const dumped = "/tmp/fv-prompt-dump/ko-a2.txt"
if (!existsSync(dumped)) throw new Error("run scripts/beginner-probe.py once to dump the live prompts")
const system = readFileSync(dumped, "utf8")
const model = process.env.CLAUDE_REPLY_MODEL ?? "claude-haiku-5-5"
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
let failures = 0
const check = (name, ok, detail = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${name} ${detail}`); if (!ok) failures++ }
const timed = async (e, h, signal = new AbortController().signal) => {
  const t0 = Date.now(); let first = null
  const text = await e.generate(h, signal, () => { if (first === null) first = Date.now() - t0 })
  return { text, first }
}
const call = [
  { role: "model", text: "안녕! 요즘 어떻게 지내?" },
  { role: "user", text: "음... 회사 일 때문에 좀 바빠." },
  { role: "model", text: "아, 바쁘구나. 오늘도 회사 갔어?" },
  { role: "user", text: "응, 갔어. 지금 집에 왔어." },
]

// 1. A call that opens on our greeting answers, in the target language.
{
  const e = new ReplyEngine({ apiKey, anthropicKey, model, fallbackModel: "gemini-3.1-flash-lite", system })
  const a = await timed(e, call.slice(0, 2))
  check("1 answers a greeting-first call", /[가-힣]/.test(a.text), `${a.first}ms "${a.text.slice(0, 60)}"`)

  // 2. The next turn reads the cached system prompt + settled prefix.
  await wait(500)
  const before = e.usage.cachedTokens
  const b = await timed(e, call)
  const u = e.usageByModel.get(model)
  check("2 cache read on the next turn", e.usage.cachedTokens > before + 1000,
    `cached=${e.usage.cachedTokens} write=${u.cacheWriteTokens} prompt=${u.promptTokens} ${b.first}ms`)

  // 3. Two learner lines in a row (a reopened turn) and a steer.
  e.steer = "COACH MODE. The learner is studying: \"피곤하다\". If it fits, you may end with a question whose natural answer uses it."
  const c = await timed(e, [...call, { role: "user", text: "근데 좀..." }])
  check("3 adjacent learner lines + steer", c.text.length > 0, `"${c.text.slice(0, 60)}"`)
  e.steer = ""

  // 4. Barge-in: abort mid-stream resolves with what was written.
  const ac = new AbortController()
  const p = e.generate(call, ac.signal, () => ac.abort())
  const d = await p
  check("4 abort keeps the partial", typeof d === "string", `"${d.slice(0, 30)}"`)
  e.dispose()
}

// 5. A bad Anthropic key: the hedge answers on Gemini at once.
{
  const e = new ReplyEngine({ apiKey, anthropicKey: "sk-ant-bad", model, fallbackModel: "gemini-3.1-flash-lite", system })
  let fellBack = ""
  e.onFallback = (x) => { fellBack = x }
  const r = await timed(e, call)
  check("5 Claude refused → Gemini answers", r.text.length > 0 && fellBack.includes("gemini"), `${r.first}ms ${fellBack}`)
}

// 6. Latency side by side on the same history.
for (const m of [model, "gemini-3.6-flash"]) {
  const e = new ReplyEngine({ apiKey, anthropicKey, model: m, fallbackModel: m, system })
  const firsts = []
  for (let i = 0; i < 4; i++) firsts.push((await timed(e, call)).first)
  console.log(`     ${m.padEnd(18)} first token ms: ${firsts.join(", ")}`)
  e.dispose()
}
process.exit(failures ? 1 : 0)
