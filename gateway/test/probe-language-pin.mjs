#!/usr/bin/env node
// Does the language pin hold? A/B the SAME audio through the transcriber with
// three different setup instructions — none, the old script-based sentence,
// and the current `languagePin` read live out of src/transcriber.ts.
//
// Why this exists: a learner reported their German being written down as some
// other language (2026-09-15), and there is no telemetry on that failure — so
// the only way to tell whether a prompt change helped is to run one recording
// through both prompts and read the two transcripts side by side.
//
// Record a sample first (speak the target language, your real accent — an
// accented learner is the whole case being tested):
//   node test/probe-language-pin.mjs --record 8 --out de-sample.wav
// Then compare:
//   node test/probe-language-pin.mjs --wav de-sample.wav --language de --runs 2
//
// Language ID is stochastic, so --runs matters: one clean run proves nothing.

import { spawn } from "node:child_process"
import { readFileSync, writeFileSync } from "node:fs"
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

const MODEL = "models/gemini-3.5-transcribe-live"
const LANGUAGE_NAMES = {
  en: "English", de: "German", ko: "Korean", ja: "Japanese",
  es: "Spanish", fr: "French", zh: "Chinese",
}

if (args.record !== undefined) {
  await record(Number(args.record) || 8, args.out || join(here, "sample.wav"))
  process.exit(0)
}

const wav = args.wav
if (!wav) {
  console.error("usage: --wav <file.wav> --language de [--runs 2]   |   --record <seconds> [--out f.wav]")
  process.exit(1)
}
const language = args.language ?? "de"
const name = LANGUAGE_NAMES[language.toLowerCase().split("-")[0]] ?? language
const runs = Number(args.runs) || 1
const pcm = readFileSync(wav).subarray(44)
console.log(`${wav}: ${(pcm.length / 2 / 16000).toFixed(1)}s of audio, target ${name}\n`)

// The old instruction is frozen here on purpose: it is what shipped until
// 2026-09-15 and the point is to compare against it, not to track it.
const OLD = `Transcribe the speaker's ${name} exactly as heard. Output only `
  + `${name} text — never another script, even for the first words of an utterance.`

const variants = [
  ["none", null],
  ["old (script rule)", OLD],
  ["new (languagePin)", currentPin(name)],
]

for (let run = 1; run <= runs; run++) {
  for (const [label, instruction] of variants) {
    const heard = await transcribe(instruction)
    console.log(`run ${run}  ${label.padEnd(18)} ${heard || "(nothing)"}`)
  }
  if (run < runs) console.log("")
}

/** The instruction the gateway actually sends today, read out of the source so
 *  this probe can never drift from it. */
function currentPin(languageName) {
  const src = readFileSync(join(here, "..", "src", "transcriber.ts"), "utf8")
  const fn = src.slice(src.indexOf("function languagePin"))
  const start = fn.indexOf("return [")
  const end = fn.indexOf('].join("\\n")')
  if (start < 0 || end < 0) throw new Error("languagePin not found in src/transcriber.ts")
  const body = fn.slice(start, end) + '].join("\\n")'
  return new Function("name", body)(languageName)
}

function transcribe(instruction) {
  return new Promise((resolve) => {
    const ws = new WebSocket(
      `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${env.GEMINI_API_KEY}`,
    )
    let final = ""
    let interim = ""
    const done = (v) => { try { ws.close() } catch {} ; resolve(v) }
    const timer = setTimeout(() => done(final || `TIMEOUT (interim: ${interim})`), 60000)
    ws.onopen = () => ws.send(JSON.stringify({
      setup: {
        model: MODEL,
        generationConfig: { responseModalities: ["TEXT"] },
        ...(instruction ? { systemInstruction: { parts: [{ text: instruction }] } } : {}),
        realtimeInputConfig: { automaticActivityDetection: {} },
      },
    }))
    ws.onmessage = async (ev) => {
      const text = typeof ev.data === "string"
        ? ev.data
        : Buffer.from(await ev.data.arrayBuffer?.() ?? ev.data).toString()
      let msg
      try { msg = JSON.parse(text) } catch { return }
      if (msg.setupComplete !== undefined) return void stream(ws)
      const i = msg.serverContent?.interimInputTranscription?.text
      if (i) interim = i
      const f = msg.serverContent?.inputTranscription?.text
      if (f?.trim()) {
        // Several utterances can come out of one recording — keep them all.
        final = final ? `${final} ${f.trim()}` : f.trim()
      }
    }
    ws.onclose = () => { clearTimeout(timer); resolve(final || `(closed, interim: ${interim})`) }
    ws.onerror = () => { clearTimeout(timer); resolve("(socket error)") }

    async function stream(sock) {
      const FRAME = 3200 // 100 ms
      for (let off = 0; off < pcm.length; off += FRAME) {
        sock.send(JSON.stringify({
          realtimeInput: {
            audio: { data: pcm.subarray(off, off + FRAME).toString("base64"), mimeType: "audio/pcm;rate=16000" },
          },
        }))
        await new Promise((r) => setTimeout(r, 100))
      }
      // The final transcript is the endpoint signal, and it only arrives in
      // the silence AFTER speech — without this tail there is nothing to read.
      const silence = Buffer.alloc(FRAME).toString("base64")
      for (let i = 0; i < 25; i++) {
        sock.send(JSON.stringify({ realtimeInput: { audio: { data: silence, mimeType: "audio/pcm;rate=16000" } } }))
        await new Promise((r) => setTimeout(r, 100))
      }
      clearTimeout(timer)
      done(final)
    }
  })
}

/** Same capture path as live-talk.mjs, written out as a 16 kHz mono WAV. */
function record(seconds, out) {
  return new Promise((resolve) => {
    console.log(`recording ${seconds}s from the default mic — speak now…`)
    const chunks = []
    const mic = spawn("ffmpeg", [
      "-hide_banner", "-loglevel", "error",
      "-f", "avfoundation", "-i", ":default",
      "-t", String(seconds),
      "-ar", "16000", "-ac", "1", "-f", "s16le", "-",
    ])
    mic.stdout.on("data", (c) => chunks.push(c))
    mic.stderr.on("data", (d) => process.stderr.write(d))
    mic.on("exit", () => {
      const body = Buffer.concat(chunks)
      writeFileSync(out, Buffer.concat([wavHeader(body.length), body]))
      console.log(`wrote ${out} (${(body.length / 2 / 16000).toFixed(1)}s)`)
      resolve()
    })
  })
}

function wavHeader(bytes) {
  const h = Buffer.alloc(44)
  h.write("RIFF", 0); h.writeUInt32LE(36 + bytes, 4); h.write("WAVE", 8)
  h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20)
  h.writeUInt16LE(1, 22); h.writeUInt32LE(16000, 24); h.writeUInt32LE(32000, 28)
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34)
  h.write("data", 36); h.writeUInt32LE(bytes, 40)
  return h
}
