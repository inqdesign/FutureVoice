// Does the wrong-script re-read (src/reread.ts) answer, and in the target
// script? Sends a WAV through the same request shape.
//   node test/probe-reread.mjs [file.wav] [lang] [model]
import { readFileSync } from "node:fs"
const [file = "test/hello16k.wav", lang = "en", model = "gemini-3.1-flash-lite"] = process.argv.slice(2)
const key = process.env.GEMINI_API_KEY
  ?? readFileSync(new URL("../.dev.vars", import.meta.url), "utf8").match(/^GEMINI_API_KEY\s*=\s*"?([^"\n]+)/m)?.[1]
const wavB64 = readFileSync(file).toString("base64")
const system = `You transcribe a language LEARNER speaking ${lang === "en" ? "English" : lang}. Reply with the transcript alone, in its own writing system. If the audio holds only hesitation sounds or no words at all, reply with nothing.`
const t0 = Date.now()
const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`, {
  method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts: [{ inlineData: { mimeType: "audio/wav", data: wavB64 } }, { text: "Transcribe this." }] }],
    generationConfig: { maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" } },
  }),
})
const json = await res.json()
console.log(res.status, `${Date.now() - t0}ms`, JSON.stringify(json.candidates?.[0]?.content?.parts ?? json).slice(0, 300))
