#!/usr/bin/env node
// End-to-end latency probe for the gateway — no app build needed.
//
// Streams a 16 kHz mono s16le WAV at realtime pace, prints every event with a
// timestamp, and writes the reply audio to out.wav. The number that matters:
// the gap between the last audio frame you sent (or `user_turn`) and the
// first reply PCM frame — that IS the "speech end -> voice" latency the whole
// gateway exists to shrink.
//
// Usage:
//   node test/talk.mjs --url ws://localhost:8787/call --wav hello16k.wav \
//     [--token <supabase-jwt>] [--voice <voice_id>]
//
// Against `wrangler dev` with DEV_ALLOW_ANON=1 in .dev.vars, token/voice can
// be anything. Needs Node >= 22 (global WebSocket).

import { readFileSync, writeFileSync } from "node:fs"

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith("--")) acc.push([a.slice(2), all[i + 1] ?? ""])
    return acc
  }, []),
)
const url = args.url ?? "ws://localhost:8787/call"
const wavPath = args.wav
if (!wavPath) { console.error("--wav <16k mono s16le wav> required"); process.exit(1) }

const wav = readFileSync(wavPath)
const pcm = wav.subarray(44) // naive header skip; use a plain PCM wav
const FRAME = 3200           // 100 ms @ 16 kHz s16 mono

const t0 = Date.now()
const stamp = () => `[${String(Date.now() - t0).padStart(6)}ms]`
let sampleRate = 22050
let lastSentAt = 0
let firstAudioAt = 0
const replyChunks = []

const ws = new WebSocket(url)
ws.binaryType = "arraybuffer"

ws.onopen = () => {
  console.log(stamp(), "open")
  ws.send(JSON.stringify({
    type: "start",
    token: args.token ?? "",
    voiceId: args.voice ?? "test-voice",
    language: "en",
    system: "You are the user's fluent future self. Reply in one or two short spoken sentences.",
  }))
}

ws.onmessage = (ev) => {
  if (typeof ev.data === "string") {
    const msg = JSON.parse(ev.data)
    console.log(stamp(), msg.type, msg.text ?? msg.message ?? "")
    if (msg.type === "ready") streamMic()
    if (msg.type === "audio_start") sampleRate = msg.sampleRate
    if (msg.type === "audio_end") finish()
    if (msg.type === "error") { console.error(stamp(), "ERROR", msg); process.exit(1) }
    return
  }
  if (!firstAudioAt) {
    firstAudioAt = Date.now()
    console.log(stamp(), `*** first reply audio — ${firstAudioAt - lastSentAt} ms after last mic frame ***`)
  }
  replyChunks.push(Buffer.from(ev.data))
}

async function streamMic() {
  for (let off = 0; off < pcm.length; off += FRAME) {
    ws.send(pcm.subarray(off, off + FRAME))
    lastSentAt = Date.now()
    await new Promise((r) => setTimeout(r, 100))
  }
  console.log(stamp(), "mic done — sending 3 s of silence for the VAD")
  // lastSentAt deliberately stays at the last SPEECH frame: the latency that
  // matters is speech-end -> voice, and silence frames aren't speech.
  const silence = Buffer.alloc(FRAME)
  for (let i = 0; i < 30; i++) {
    ws.send(silence)
    await new Promise((r) => setTimeout(r, 100))
  }
}

function finish() {
  const body = Buffer.concat(replyChunks)
  writeFileSync("out.wav", Buffer.concat([wavHeader(body.length, sampleRate), body]))
  console.log(stamp(), `wrote out.wav (${body.length} bytes @ ${sampleRate} Hz)`)
  ws.send(JSON.stringify({ type: "end" }))
  setTimeout(() => process.exit(0), 200)
}

function wavHeader(dataLen, rate) {
  const h = Buffer.alloc(44)
  h.write("RIFF", 0); h.writeUInt32LE(36 + dataLen, 4); h.write("WAVE", 8)
  h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20)
  h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24)
  h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34)
  h.write("data", 36); h.writeUInt32LE(dataLen, 40)
  return h
}
