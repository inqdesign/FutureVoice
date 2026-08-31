#!/usr/bin/env node
// Dump every message gemini-3.5-transcribe-live sends for a real utterance,
// so the gateway's parser is written against observed shapes, not guessed
// ones. Streams test/hello16k.wav at realtime pace, then 3 s of silence.
// Run: node --experimental-websocket test/probe-transcribe.mjs

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)
const pcm = readFileSync(join(here, "hello16k.wav")).subarray(44)
const FRAME = 3200

const t0 = Date.now()
const stamp = () => `[${String(Date.now() - t0).padStart(6)}ms]`

const ws = new WebSocket(
  `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${env.GEMINI_API_KEY}`,
)
ws.onopen = () => {
  ws.send(JSON.stringify({
    setup: {
      model: "models/gemini-3.5-transcribe-live",
      generationConfig: { responseModalities: ["TEXT"] },
    },
  }))
}
ws.onmessage = async (ev) => {
  const text = typeof ev.data === "string"
    ? ev.data
    : Buffer.from(await ev.data.arrayBuffer?.() ?? ev.data).toString()
  console.log(stamp(), text.slice(0, 500))
  if (text.includes("setupComplete")) stream()
}
ws.onclose = (ev) => { console.log(stamp(), "CLOSED", ev.code, ev.reason); process.exit(0) }

async function stream() {
  for (let off = 0; off < pcm.length; off += FRAME) {
    ws.send(JSON.stringify({
      realtimeInput: {
        audio: {
          data: pcm.subarray(off, off + FRAME).toString("base64"),
          mimeType: "audio/pcm;rate=16000",
        },
      },
    }))
    await new Promise((r) => setTimeout(r, 100))
  }
  console.log(stamp(), "--- audio done, 3s silence ---")
  const silence = Buffer.alloc(FRAME).toString("base64")
  for (let i = 0; i < 30; i++) {
    ws.send(JSON.stringify({
      realtimeInput: { audio: { data: silence, mimeType: "audio/pcm;rate=16000" } },
    }))
    await new Promise((r) => setTimeout(r, 100))
  }
  console.log(stamp(), "--- done, closing in 3s ---")
  setTimeout(() => ws.close(), 3000)
}
