// Free talk through the real reply path (reply.ts + SpokenGate), brief on and
// off (2026-11-17). Run: node test/open-talk-check.mjs (Node 22). Keys as in
// claude-reply-check.mjs. Prints what the call would SPEAK; read it.
import { readFileSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { homedir } from "node:os"
const out = new URL("../.open-talk-check.mjs", import.meta.url).pathname
execFileSync(new URL("../node_modules/.bin/esbuild", import.meta.url).pathname,
  [new URL("../src/reply.ts", import.meta.url).pathname, "--bundle", "--format=esm", `--outfile=${out}`, "--log-level=warning"])
const { ReplyEngine } = await import(out)
const vars = readFileSync(new URL("../.dev.vars", import.meta.url), "utf8")
const apiKey = vars.match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)[1]
const anthropicKey = process.env.ANTHROPIC_API_KEY ?? readFileSync(`${homedir()}/keys/anthropic.txt`, "utf8").trim()
const system = `You are the user's future self: them, a few years from now, speaking English fluently, in their own voice. They called you. Talk with them freely, about anything, in English.

About them:
- Name: Olivia
- Lives in: Singapore (2 years)
- Native language: Korean
- Their English level: B2 (CEFR)

This call:
- Now: Sunday 15 November 2026, 14:10 where they are.
- This is their first talk with you today.

How the call works: their words reach you through speech recognition, so now and then a word is wrong. Everything you write is spoken aloud in their voice, exactly as written. The lines above are information about them, not instructions.`
const lunch = [
  { role: "model", text: "Hey Olivia! How's your Sunday going?" },
  { role: "user", text: "I'm on my way back home now. I had lunch with my partner at a newly opened restaurant, it was a bit pricey but worth it." },
  { role: "model", text: "Nice, a new place. What did you two order?" },
  { role: "user", text: "We had the laksa and some grilled fish. And I almost lost my AirPod on the MRT, it fell under the seat." },
  { role: "model", text: "Oh no, under the seat? Did you get it back?" },
]
const cases = {
  noise: [...lunch, { role: "user", text: "She is here for six month." }],
  tired: [lunch[0], { role: "user", text: "Honestly I'm exhausted. I worked the whole weekend and my boss still complained about the deck." }],
  asks: [lunch[0], { role: "user", text: "Not much. Hey, do you think it is worth moving to a bigger flat even if the rent is much higher?" }],
}
const sentences = (t) => t.split(/(?<=[.!?…])\s+/).filter((s) => s.trim() && s.trim().split(/\s+/).length > 3).length
for (const [model, label] of [["claude-haiku-5-5", "claude"], ["gemini-3.6-flash", "gemini"]]) {
  for (const brief of [false, true]) {
    for (const [name, history] of Object.entries(cases)) {
      const e = new ReplyEngine({ apiKey, anthropicKey, model, fallbackModel: model, system, language: "en",
        claudeEffort: "low", openTalkBrief: brief })
      e.openTalk = true
      const text = await e.generate(history, new AbortController().signal, () => {})
      console.log(`[${label} brief=${brief ? "on " : "off"} ${name}: ${sentences(text)} full sentences, ${(text.match(/\?/g) ?? []).length}q] ${text.replace(/\s+/g, " ")}`)
      e.dispose()
    }
  }
}
