#!/usr/bin/env node
// Can the gateway STOP forwarding the phone's echo-muted silence to
// gemini-3.5-transcribe-live? The phone sends exact zeros for the whole time
// the fluent self is audible, and Google bills the live model by audio
// streamed in — so that silence is paid for. This plays the shape of a call:
// utterance 1, a long "fluent self is talking" stretch, utterance 2 (spoken
// the instant the stretch ends — a barge-in's worst case), and compares:
//   stream  — today: zeros for the whole stretch
//   gap     — zeros for TAIL_MS, then nothing until the next real frame
//   end     — as gap, plus `audioStreamEnd` when the forwarding stops
//   keep    — as gap, but one 100 ms zero frame every KEEP_MS: the live
//             socket is aborted (1008) after a long enough gap with nothing
// Reported per mode: each final transcript and ms from the end of its audio.
// Run: node --experimental-websocket test/probe-transcribe-gap.mjs u1.wav u2.wav [runs]

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)
function pcmOf(path) {
  const b = readFileSync(path)
  const i = b.indexOf("data")
  return b.subarray(i + 8)
}
const [u1, u2] = [pcmOf(process.argv[2]), pcmOf(process.argv[3])]
const runs = Number(process.argv[4] ?? 2)
const FRAME = 3200 // 100 ms
const STRETCH_MS = Number(process.env.STRETCH_MS ?? 12_000)
const TAIL_MS = Number(process.env.TAIL_MS ?? 2000)
const KEEP_MS = Number(process.env.KEEP_MS ?? 5000)
const MODES = (process.env.MODES ?? "stream,gap,end,keep").split(",")
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function session(mode) {
  return new Promise((resolve) => {
    const ws = new WebSocket(
      `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${env.GEMINI_API_KEY}`,
    )
    const finals = []
    let audioEnd = 0
    let sentMs = 0
    let closed = null
    const send = (buf) => {
      ws.send(JSON.stringify({ realtimeInput: { audio: { data: buf.toString("base64"), mimeType: "audio/pcm;rate=16000" } } }))
      sentMs += 100
    }
    ws.onopen = () => ws.send(JSON.stringify({ setup: {
      model: "models/gemini-3.5-transcribe-live",
      generationConfig: { responseModalities: ["TEXT"] },
      systemInstruction: { parts: [{ text: "The speaker is speaking English." }] },
      realtimeInputConfig: { automaticActivityDetection: {} },
    } }))
    ws.onclose = (ev) => { closed = `${ev.code} ${ev.reason}` }
    ws.onmessage = async (ev) => {
      const text = typeof ev.data === "string" ? ev.data : Buffer.from(await ev.data.arrayBuffer?.() ?? ev.data).toString()
      const m = JSON.parse(text)
      if (m.setupComplete) run()
      const fin = m.serverContent?.inputTranscription?.text
      if (fin) finals.push({ text: fin.trim(), afterAudioMs: Date.now() - audioEnd })
    }
    const zero = Buffer.alloc(FRAME)
    async function speak(pcm) {
      for (let off = 0; off < pcm.length; off += FRAME) {
        const f = Buffer.alloc(FRAME); pcm.copy(f, 0, off, Math.min(off + FRAME, pcm.length))
        send(f); await sleep(100)
      }
      audioEnd = Date.now()
    }
    async function quiet(ms) {
      for (let t = 0; t < ms; t += 100) {
        if (mode === "stream" || t < TAIL_MS) send(zero)
        else if (mode === "keep" && (t - TAIL_MS) % KEEP_MS === 0) send(zero)
        else if (mode === "end" && t === TAIL_MS) ws.send(JSON.stringify({ realtimeInput: { audioStreamEnd: true } }))
        await sleep(100)
      }
    }
    async function run() {
      await speak(u1)
      await quiet(STRETCH_MS)
      await speak(u2)
      for (let i = 0; i < 40; i++) { send(zero); await sleep(100) } // the room after the line
      await sleep(1000)
      ws.close()
      resolve({ mode, sentSeconds: sentMs / 1000, finals, closed })
    }
  })
}

for (let r = 0; r < runs; r++) {
  const out = await Promise.all(MODES.map(session))
  for (const o of out) {
    console.log(`run ${r} ${o.mode.padEnd(6)} sent ${o.sentSeconds}s  closed=${o.closed}`)
    for (const f of o.finals) console.log(`    +${String(f.afterAudioMs).padStart(6)}ms  ${f.text}`)
  }
}
