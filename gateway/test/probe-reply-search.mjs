#!/usr/bin/env node
// What does google_search grounding cost the reply call? (2026-10-05)
// Runs the app's LIVE conversation prompt (dumped by ConversationPromptDumpTests
// into /tmp/fv-prompt-dump) with the gateway's reply settings, with and without
// the search tool, over ordinary turns and time-sensitive questions, and prints
// time-to-first-text, total time, whether a search ran, and the reply.
// Run: node test/probe-reply-search.mjs   (RUNS=3 MODEL=gemini-3.6-flash LANG=ko)

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)
const MODEL = process.env.MODEL ?? "gemini-3.6-flash"
const RUNS = Number(process.env.RUNS ?? 3)
const LANG = process.env.LANG_CODE ?? "ko"
const system = readFileSync(`/tmp/fv-prompt-dump/${LANG}-b1.txt`, "utf8") +
  "\n\nWHEN THIS IS:\n- Today is Monday, 5 October 2026, 14:10 (afternoon).\n" + (process.env.EXTRA ?? "")

const CASES = {
  ko: [
    ["plain", "어제 카페에서 오랜만에 친구 만나서 진짜 재밌게 얘기했어."],
    ["plain", "요즘 회사 일이 너무 많아서 좀 피곤해."],
    ["plain", "데미안 읽어봤어? 어땠어?"],
    ["fresh", "요즘 나온 최신 아이폰이 뭐야?"],
    ["fresh", "지금 미국 대통령이 누구야?"],
    ["fresh", "지난 월드컵 어디가 우승했어?"],
  ],
  en: [
    ["plain", "I went to a cafe yesterday and had a really nice chat with an old friend."],
    ["fresh", "What's the newest iPhone right now?"],
    ["fresh", "Who won the last World Cup?"],
  ],
}

async function run(text, search) {
  const t0 = Date.now()
  const body = {
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: "model", parts: [{ text: LANG === "ko" ? "안녕! 요즘 어때?" : "Hey! How's it going?" }] },
               { role: "user", parts: [{ text }] }],
    generationConfig: { maxOutputTokens: 1024, thinkingConfig: { thinkingLevel: "minimal" } },
  }
  if (search) body.tools = [{ google_search: {} }]
  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:streamGenerateContent?alt=sse&key=${env.GEMINI_API_KEY}`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
  if (!resp.ok) return { err: `HTTP ${resp.status} ${(await resp.text()).slice(0, 200)}` }
  const reader = resp.body.getReader(); const dec = new TextDecoder()
  let buf = "", full = "", first = null, queries = []
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    const lines = buf.split("\n"); buf = lines.pop() ?? ""
    for (const l of lines) {
      if (!l.startsWith("data:")) continue
      let c; try { c = JSON.parse(l.slice(5)) } catch { continue }
      const cand = c?.candidates?.[0]
      for (const p of cand?.content?.parts ?? []) if (typeof p.text === "string" && p.text) { if (first === null) first = Date.now() - t0; full += p.text }
      const q = cand?.groundingMetadata?.webSearchQueries
      if (Array.isArray(q) && q.length) queries = q
    }
  }
  return { first, total: Date.now() - t0, queries, full: full.trim() }
}

for (const [kind, text] of CASES[LANG] ?? CASES.ko) {
  for (const search of [false, true]) {
    const rs = []
    for (let i = 0; i < RUNS; i++) rs.push(await run(text, search))
    const ok = rs.filter((r) => !r.err)
    const med = (a) => a.sort((x, y) => x - y)[Math.floor(a.length / 2)]
    console.log(`[${kind}] ${search ? "SEARCH" : "none  "} first ${ok.map((r) => r.first).join("/")}ms (med ${med(ok.map((r) => r.first))}) total med ${med(ok.map((r) => r.total))}ms searched ${ok.filter((r) => r.queries.length).length}/${ok.length}  ${text}`)
    for (const r of rs) console.log(r.err ? `   ! ${r.err}` : `   ${r.queries.length ? "🔎" + JSON.stringify(r.queries) + " " : ""}→ ${r.full.replace(/\n/g, " ")}`)
  }
}
