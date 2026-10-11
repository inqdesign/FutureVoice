#!/usr/bin/env node
// Does SpeechGate (src/speech-gate.ts) change what gemini-3.5-transcribe-live
// hears? Plays one WAV in real time twice — every frame (today), then only the
// frames the gate lets through — and prints each mode's finals, when each
// final arrived, and how much audio went upstream.
//
// The WAV should look like a call: speech, thinking pauses with room noise in
// them (16 kHz mono s16le). Built 2026-10-11 from a 36 s read with two 6 s
// pauses, mixed with pink noise at amplitude 0.004 (quiet room) and brown noise
// at 0.05 (café) via ffmpeg anoisesrc + amix.
//
// Run: node --experimental-strip-types --experimental-websocket \
//        test/probe-speech-gate.mjs call.wav [language]

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { SpeechGate } from "../src/speech-gate.ts"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)
const wav = readFileSync(process.argv[2])
const pcm = wav.subarray(wav.indexOf("data") + 8)
const language = process.argv[3] ?? "English"
const FRAME = 3200 // 100 ms, the phone's frame size
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function run(mode) {
  return new Promise((resolve) => {
    const ws = new WebSocket(
      `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${env.GEMINI_API_KEY}`,
    )
    const gate = mode === "gate" ? new SpeechGate() : null
    const finals = []
    let current = ""
    let t0 = 0
    let sentMs = 0
    ws.onopen = () => ws.send(JSON.stringify({ setup: {
      model: "models/gemini-3.5-transcribe-live",
      generationConfig: { responseModalities: ["TEXT"] },
      systemInstruction: { parts: [{ text: `The speaker is speaking ${language}.` }] },
      realtimeInputConfig: { automaticActivityDetection: {} },
    } }))
    ws.onmessage = async (ev) => {
      const raw = typeof ev.data === "string" ? ev.data : Buffer.from(await ev.data.arrayBuffer()).toString()
      const m = JSON.parse(raw)
      if (m.setupComplete) {
        t0 = Date.now()
        for (let i = 0; i < pcm.length; i += FRAME) {
          const frame = pcm.subarray(i, i + FRAME)
          const ab = frame.buffer.slice(frame.byteOffset, frame.byteOffset + frame.byteLength)
          const out = gate ? gate.push(ab) : [ab]
          for (const f of out) {
            ws.send(JSON.stringify({ realtimeInput: { audio: {
              data: Buffer.from(f).toString("base64"), mimeType: "audio/pcm;rate=16000" } } }))
            sentMs += f.byteLength / 32
          }
          await sleep(100)
        }
        // A tail of silence like a call's, then stop.
        await sleep(4000)
        ws.close()
        return
      }
      // The same two signals GeminiTranscriber feeds the gate in production.
      const sc = m.serverContent
      if (sc?.interimInputTranscription?.text) { gate?.noteInterim(); current = sc.interimInputTranscription.text }
      if (sc?.inputTranscription?.text?.trim()) {
        gate?.noteFinal()
        finals.push({ at: ((Date.now() - t0) / 1000).toFixed(1), text: sc.inputTranscription.text.trim() })
        current = ""
      }
    }
    ws.onclose = () => {
      if (current.trim()) finals.push({ at: "unfinished", text: current.trim() })
      resolve({ mode, finals, sentS: (sentMs / 1000).toFixed(1), totalS: (pcm.length / 32000).toFixed(1) })
    }
  })
}

for (const mode of ["stream", "gate"]) {
  const r = await run(mode)
  console.log(`\n== ${mode}: sent ${r.sentS}s of ${r.totalS}s`)
  for (const f of r.finals) console.log(`  [${f.at}s] ${f.text}`)
}
