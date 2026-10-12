#!/usr/bin/env node
// Time to first audio over a WARM streaming socket — what a call's reply
// actually waits on — for ElevenLabs (the gateway's path today) and Cartesia
// (the candidate), same sentences, same speed, alternating so network drift
// hits both equally. Also reports whether word timestamps come back
// (karaoke and the rhythm grade depend on them).
//
// ElevenLabs is driven exactly as gateway/src/eleven-tts.ts drives it:
// multi-stream-input, turbo v2.5, auto_mode, one sentence per context,
// production voice settings. Cartesia: /tts/websocket, sonic-3.6, one
// context per sentence, continue:false, add_timestamps.
//
// Run: node --experimental-websocket test/probe-tts-ttfb.mjs [rounds]
//   EL_VOICE   ElevenLabs voice id   (default: the founder's clone)
//   CA_VOICE   Cartesia voice id     (default: the founder's test clone)
//   ONLY       eleven | cartesia     (skip the other)
// Keys: ELEVENLABS_API_KEY from .dev.vars, Cartesia from ~/keys/cartesia.txt.

import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { randomUUID } from "node:crypto"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)
const rounds = Number(process.argv[2] ?? 3)
const ONLY = process.env.ONLY ?? ""
const EL_VOICE = process.env.EL_VOICE ?? "31fQLzd8XYV6VPyG3GWA"
const CA_VOICE = process.env.CA_VOICE ?? "196f95cd-a639-472e-b28d-b9bb93bb6a98"
const SPEED = 0.9

const LINES = [
  ["en", "Oh nice, so you finally tried that place?"],
  ["en", "I keep hearing about it, but I never get around to going."],
  ["de", "Ach, echt? Das klingt richtig gut."],
  ["ja", "へえ、そうなんだ。"],
  ["ko", "아 진짜? 그거 완전 좋은데."],
]
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function openSocket(url, headers) {
  return new Promise((resolve, reject) => {
    // Node's WebSocket takes headers through the second (protocols/options) arg.
    const ws = new WebSocket(url, { headers })
    ws.onopen = () => resolve(ws)
    ws.onerror = (e) => reject(new Error(`socket error ${e?.message ?? ""}`))
  })
}

async function eleven() {
  const key = (env.ELEVENLABS_API_KEY ?? "").replace(/"/g, "")
  const url = `wss://api.elevenlabs.io/v1/text-to-speech/${EL_VOICE}/multi-stream-input` +
    `?model_id=eleven_turbo_v2_5&output_format=pcm_16000&auto_mode=true&inactivity_timeout=180`
  const ws = await openSocket(url, { "xi-api-key": key })
  const waiters = new Map()
  ws.onmessage = (ev) => {
    const m = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString())
    const id = m.contextId ?? m.context_id
    const w = waiters.get(id)
    if (!w) return
    if (m.audio && !w.first) w.first = performance.now()
    if (m.alignment || m.normalizedAlignment) w.timing = true
    if (m.isFinal || m.is_final) { w.end = performance.now(); w.resolve() }
  }
  return async (text) => {
    const id = randomUUID()
    const w = { first: 0, end: 0, timing: false }
    const done = new Promise((r) => { w.resolve = r })
    waiters.set(id, w)
    const t0 = performance.now()
    ws.send(JSON.stringify({ context_id: id, text: text + " ", voice_settings: {
      stability: 0.55, similarity_boost: 0.9, style: 0, use_speaker_boost: true, speed: SPEED } }))
    ws.send(JSON.stringify({ context_id: id, flush: true }))
    await Promise.race([done, sleep(10_000)])
    ws.send(JSON.stringify({ context_id: id, close_context: true }))
    return { ttfb: w.first ? w.first - t0 : NaN, total: w.end ? w.end - t0 : NaN, timing: w.timing }
  }
}

async function cartesia() {
  const key = readFileSync(join(homedir(), "keys", "cartesia.txt"), "utf8").trim()
  const url = `wss://api.cartesia.ai/tts/websocket?cartesia_version=2026-08-14`
  const ws = await openSocket(url, { "X-API-Key": key })
  const waiters = new Map()
  ws.onmessage = (ev) => {
    const m = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString())
    const w = waiters.get(m.context_id)
    if (!w) return
    if (m.type === "error") { w.error = m.message ?? m.title; w.resolve(); return }
    if (m.type === "chunk" && m.data && !w.first) w.first = performance.now()
    if (m.type === "timestamps" && m.word_timestamps?.words?.length) w.timing = true
    if (m.type === "done" || m.done === true) { w.end = performance.now(); w.resolve() }
  }
  return async (text, lang) => {
    const id = randomUUID()
    const w = { first: 0, end: 0, timing: false }
    const done = new Promise((r) => { w.resolve = r })
    waiters.set(id, w)
    const t0 = performance.now()
    ws.send(JSON.stringify({
      model_id: "sonic-3.6", transcript: text, voice: { mode: "id", id: CA_VOICE }, language: lang,
      context_id: id, continue: false, add_timestamps: true,
      output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: 16000 },
      generation_config: { speed: SPEED },
    }))
    await Promise.race([done, sleep(10_000)])
    if (w.error) throw new Error(`cartesia: ${w.error}`)
    return { ttfb: w.first ? w.first - t0 : NaN, total: w.end ? w.end - t0 : NaN, timing: w.timing }
  }
}

const vendors = []
if (ONLY !== "cartesia") vendors.push(["eleven", await eleven()])
if (ONLY !== "eleven") vendors.push(["cartesia", await cartesia()])
const results = Object.fromEntries(vendors.map(([n]) => [n, []]))

// One untimed warm-up each (first request on a socket pays setup).
for (const [, say] of vendors) await say(LINES[0][1], LINES[0][0])

for (let r = 0; r < rounds; r++) {
  for (const [lang, text] of LINES) {
    for (const [name, say] of vendors) {
      const res = await say(text, lang)
      results[name].push({ lang, ...res })
      console.log(`${name.padEnd(8)} ${lang}  first audio ${res.ttfb.toFixed(0).padStart(5)} ms   done ${res.total.toFixed(0).padStart(5)} ms   word timings ${res.timing ? "yes" : "NO"}`)
      await sleep(300)
    }
  }
}

const median = (xs) => { const s = xs.filter((x) => !Number.isNaN(x)).sort((a, b) => a - b); return s[Math.floor(s.length / 2)] }
const pct = (xs, p) => { const s = xs.filter((x) => !Number.isNaN(x)).sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(s.length * p))] }
console.log("\nfirst audio (ms)   median   p90    | timings")
for (const [name] of vendors) {
  const xs = results[name].map((x) => x.ttfb)
  console.log(`${name.padEnd(17)} ${String(median(xs)?.toFixed(0)).padStart(6)} ${String(pct(xs, 0.9)?.toFixed(0)).padStart(6)}    | ${results[name].every((x) => x.timing) ? "all" : results[name].filter((x) => x.timing).length + "/" + results[name].length}`)
}
process.exit(0)
