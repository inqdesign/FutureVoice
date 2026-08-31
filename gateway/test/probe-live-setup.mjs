#!/usr/bin/env node
// Probe which (model, responseModalities) combos the Live API accepts.
// Opens a BidiGenerateContent socket per combo, sends setup, reports
// setupComplete vs the close reason. Key comes from ../.dev.vars.
// Run: node --experimental-websocket test/probe-live-setup.mjs [v1alpha]

import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const env = Object.fromEntries(
  readFileSync(join(here, "..", ".dev.vars"), "utf8")
    .split("\n").filter((l) => l.includes("=")).map((l) => l.split(/=(.*)/s).slice(0, 2)),
)
const version = process.argv[2] === "v1alpha" ? "v1alpha" : "v1beta"

const combos = []
for (const model of [
  "models/gemini-3.1-flash-live-preview",
  "models/gemini-2.5-flash-native-audio-latest",
  "models/gemini-3.5-transcribe-live",
  "models/gemini-live-2.5-flash-preview",
  "models/gemini-2.0-flash-live-001",
]) {
  for (const modalities of [["TEXT"], ["AUDIO"]]) {
    combos.push({ model, modalities })
  }
}

for (const { model, modalities } of combos) {
  const result = await probe(model, modalities)
  console.log(`${version} ${model} ${JSON.stringify(modalities)} -> ${result}`)
}

function probe(model, modalities) {
  return new Promise((resolve) => {
    const ws = new WebSocket(
      `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.${version}.GenerativeService.BidiGenerateContent?key=${env.GEMINI_API_KEY}`,
    )
    const timer = setTimeout(() => { try { ws.close() } catch {} ; resolve("TIMEOUT") }, 8000)
    ws.onopen = () => {
      ws.send(JSON.stringify({
        setup: {
          model,
          generationConfig: { responseModalities: modalities },
        },
      }))
    }
    ws.onmessage = async (ev) => {
      const text = typeof ev.data === "string" ? ev.data : Buffer.from(await ev.data.arrayBuffer?.() ?? ev.data).toString()
      if (text.includes("setupComplete")) {
        clearTimeout(timer)
        try { ws.close() } catch {}
        resolve("OK")
      }
    }
    ws.onclose = (ev) => {
      clearTimeout(timer)
      resolve(`CLOSED ${ev.code} ${ev.reason}`)
    }
    ws.onerror = () => { /* onclose follows */ }
  })
}
