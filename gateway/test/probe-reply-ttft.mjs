#!/usr/bin/env node
// Measure time-to-first-delta of streaming generateContent under different
// thinking configs — the reply TTFT is the biggest slice of the gateway's
// turn latency, and thinking time is the suspect.
// Run: node test/probe-reply-ttft.mjs

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)

const configs = [
  ["3.6-flash low",      "gemini-3.6-flash",       { thinkingConfig: { thinkingLevel: "low" } }],
  ["3.6-flash minimal",  "gemini-3.6-flash",       { thinkingConfig: { thinkingLevel: "minimal" } }],
  ["3.6-flash none",     "gemini-3.6-flash",       { thinkingConfig: { thinkingLevel: "none" } }],
  ["3.6-flash budget0",  "gemini-3.6-flash",       { thinkingConfig: { thinkingBudget: 0 } }],
  ["3.6-flash absent",   "gemini-3.6-flash",       {}],
  ["3.1-flash-lite low", "gemini-3.1-flash-lite",  { thinkingConfig: { thinkingLevel: "low" } }],
]

for (const [label, model, extra] of configs) {
  const times = []
  let error = null
  for (let i = 0; i < 3; i++) {
    const t = await ttft(model, extra)
    if (typeof t === "number") times.push(t)
    else { error = t; break }
  }
  console.log(label.padEnd(20), error ?? `ttft ms: ${times.join(", ")}`)
}

async function ttft(model, extraGen) {
  const t0 = Date.now()
  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${env.GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: "You are the user's fluent future self. Reply in one or two short spoken sentences." }] },
        contents: [{ role: "user", parts: [{ text: "I went to a cafe yesterday and had a really nice conversation with an old friend." }] }],
        generationConfig: { maxOutputTokens: 1024, ...extraGen },
      }),
    },
  )
  if (!resp.ok) return `HTTP ${resp.status} ${(await resp.text()).slice(0, 120)}`
  const reader = resp.body.getReader()
  const decoder = new TextDecoder()
  let buf = ""
  for (;;) {
    const { done, value } = await reader.read()
    if (done) return "no delta"
    buf += decoder.decode(value, { stream: true })
    if (/"text"\s*:/.test(buf)) {
      reader.cancel().catch(() => {})
      return Date.now() - t0
    }
  }
}
