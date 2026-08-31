#!/usr/bin/env node
// LIVE conversation with the gateway from the Mac terminal — the mic streams
// continuously (ffmpeg/avfoundation), replies play through the speakers
// (ffplay), and barge-in works: speak over the reply and it stops.
//
//   node test/live-talk.mjs                    # deployed gateway
//   node test/live-talk.mjs --url ws://localhost:8787/call
//
// ⚠️  Wear EARPHONES. There is no echo cancellation on this path (the phone
// app gets it from iOS voice processing) — on open speakers the reply audio
// re-enters the mic and interrupts itself forever.
//
// Auth: mints a fresh anonymous Supabase session from ../.dev.vars, so the
// full production gate (JWT + voice ownership) is exercised. The voice is a
// counterpart PRESET (anonymous users own no clone); the learner's own clone
// works the same once the real app sends its session token.

import { spawn } from "node:child_process"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith("--")) acc.push([a.slice(2), all[i + 1] ?? ""])
    return acc
  }, []),
)
const url = args.url ?? "wss://futurevoice-gateway.futurevoice-gateway.workers.dev/call"
const voice = args.voice ?? "NDTYOmYEjbDIVCKB35i3"

// --- fresh anonymous session (1h expiry outlives any test call) ---
const auth = await fetch(`${env.SUPABASE_URL}/auth/v1/signup`, {
  method: "POST",
  headers: { apikey: env.SUPABASE_ANON_KEY, "Content-Type": "application/json" },
  body: JSON.stringify({ data: {} }),
})
if (!auth.ok) { console.error("anon sign-in failed:", await auth.text()); process.exit(1) }
const token = (await auth.json()).access_token

const t0 = Date.now()
const stamp = () => `[${String(((Date.now() - t0) / 1000).toFixed(1)).padStart(6)}s]`

let sampleRate = 22050
let player = null
let turnCommittedAt = 0
let firstAudioSeen = false

const ws = new WebSocket(url)
ws.binaryType = "arraybuffer"

ws.onopen = () => {
  ws.send(JSON.stringify({
    type: "start",
    token,
    voiceId: voice,
    language: "en",
    system: [
      "You are the user's fluent future self on a phone call — warm, casual,",
      "encouraging. Reply in one to three short spoken sentences, then keep",
      "the conversation going naturally. Speak English.",
    ].join(" "),
  }))
}

ws.onclose = (ev) => { console.log(`\n${stamp()} closed ${ev.code} ${ev.reason}`); cleanup(0) }
ws.onerror = () => { console.error(`${stamp()} socket error`); cleanup(1) }

ws.onmessage = (ev) => {
  if (typeof ev.data !== "string") {
    if (!firstAudioSeen) {
      firstAudioSeen = true
      const gap = turnCommittedAt ? Date.now() - turnCommittedAt : 0
      process.stdout.write(`\n${stamp()} 🔊 voice (+${gap} ms after turn commit)\n`)
    }
    player?.stdin.write(Buffer.from(ev.data))
    return
  }
  const msg = JSON.parse(ev.data)
  switch (msg.type) {
    case "ready":
      console.log(`${stamp()} ☎️  connected — start talking (Ctrl+C to hang up)`)
      startMic()
      break
    case "user_partial":
      process.stdout.write(`\r${stamp()} 🎤 ${msg.text.slice(-90)}`)
      break
    case "user_turn":
      turnCommittedAt = Date.now()
      firstAudioSeen = false
      process.stdout.write(`\n${stamp()} ✅ you: ${msg.text}\n`)
      break
    case "audio_start":
      sampleRate = msg.sampleRate
      startPlayer()
      break
    case "reply":
      console.log(`${stamp()} 🗣  self: ${msg.text}`)
      break
    case "audio_end":
      player?.stdin.end()
      player = null
      break
    case "interrupted":
      console.log(`\n${stamp()} ✋ interrupted — you spoke over it`)
      stopPlayer()
      break
    case "rotating":
      console.log(`${stamp()} ↻ session rotating`)
      break
    case "stats":
      break
    case "error":
      console.error(`\n${stamp()} ERROR ${msg.code}: ${msg.message}`)
      break
  }
}

let mic = null
function startMic() {
  mic = spawn("ffmpeg", [
    "-hide_banner", "-loglevel", "error",
    "-f", "avfoundation", "-i", ":default",
    "-ar", "16000", "-ac", "1", "-f", "s16le", "-",
  ])
  mic.stdout.on("data", (chunk) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(chunk)
  })
  mic.stderr.on("data", (d) => process.stderr.write(d))
  mic.on("exit", (code) => {
    if (code !== 0) console.error("\nmic exited — check macOS mic permission for your terminal app")
  })
}

function startPlayer() {
  stopPlayer()
  player = spawn("ffplay", [
    "-hide_banner", "-loglevel", "error", "-nodisp", "-autoexit",
    "-f", "s16le", "-ar", String(sampleRate), "-ac", "1", "-i", "-",
  ])
  player.stdin.on("error", () => {})
}

function stopPlayer() {
  if (player) { try { player.kill("SIGKILL") } catch {} ; player = null }
}

function cleanup(code) {
  try { mic?.kill("SIGKILL") } catch {}
  stopPlayer()
  process.exit(code)
}

process.on("SIGINT", () => {
  console.log(`\n${stamp()} hanging up`)
  try { ws.send(JSON.stringify({ type: "end" })) } catch {}
  setTimeout(() => cleanup(0), 300)
})
