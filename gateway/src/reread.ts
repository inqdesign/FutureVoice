// Second reading of one utterance, from its audio, when the live transcriber
// wrote it in the wrong SCRIPT.
//
// The live model takes no language setting (see transcriber.ts `connect`),
// only a pin in its instructions, and the pin is not enough for an accented
// learner. Measured over 14 days to 2026-09-30: English learners' finals came
// back as Devanagari — "नाइन हाउस ऑफ देम" is "nine house of them" written in
// Hindi letters — and the fluent self ANSWERED that line; a short one ("सो सो",
// the learner's "so so") was taken for a mis-scripted filler and thrown away.
// A Korean learner of English was hearing, in their own voice, replies to
// Hindi nobody spoke.
//
// So a final in the wrong script is not answered as written: the audio the
// learner produced since the previous final is sent once to an ordinary
// generateContent call with the language settled up front, and its line is
// what the turn is answered from. It costs one short flash-lite call, and
// only on the lines that were already wrong. Any failure returns null and
// the caller does what it did before.
//
// It also has to know WHICH language was spoken (2026-10-08). Told "write
// English only", the re-read wrote English for a learner who had simply
// switched to Korean — "가벼운" became "a cupboard", "이거 포인트 어떻게
// 뽑죠?" became "Ich habe heute etwas Brot." — 72 such lines from 15
// learners in two weeks, every one answered and corrected as if said. So
// when the app sends the native language, the re-read classifies first
// (`target` / `native` / `none`) and writes in the language actually spoken.
// test/probe-reread-native.mjs: 86/88 right on synthesized Korean-voiced
// lines (real Korean, Hangul-read English/German, fillers), the two misses
// labelled target but written in Hangul — which `CallSession` re-labels by
// script. The old prompt wrote a target sentence for 40/40 Korean lines.

import { base64Encode, languageName, languagePin } from "./transcriber"

const API_HOST = "https://generativelanguage.googleapis.com"

/** Wrap 16 kHz mono s16le PCM in a WAV header. */
function wav(chunks: ArrayBuffer[]): ArrayBuffer {
  const dataBytes = chunks.reduce((n, c) => n + c.byteLength, 0)
  const out = new ArrayBuffer(44 + dataBytes)
  const v = new DataView(out)
  const str = (o: number, s: string) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)) }
  const rate = 16000
  str(0, "RIFF"); v.setUint32(4, 36 + dataBytes, true); str(8, "WAVE")
  str(12, "fmt "); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true)
  v.setUint32(24, rate, true); v.setUint32(28, rate * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true)
  str(36, "data"); v.setUint32(40, dataBytes, true)
  const bytes = new Uint8Array(out)
  let o = 44
  for (const c of chunks) { bytes.set(new Uint8Array(c), o); o += c.byteLength }
  return out
}

/** Which language a re-read found the learner speaking. */
export type Spoken = "target" | "native" | "none"

/** The classifying prompt. Must stay byte-identical to
 *  test/probe-reread-native.mjs `newSystem` — that probe is its measurement. */
export function classifyingSystem(target: string, native: string): string {
  const t = languageName(target), nv = languageName(native)
  return [
    `You hear one utterance from a ${nv} speaker who is learning ${t}, in the middle of a ${t} conversation. Decide which language they actually SPOKE, then transcribe it.`,
    `"target": they spoke ${t} — however strong the ${nv} accent, however broken the grammar, however much it sounds like ${nv} sounds. Words of ${t} pronounced the ${nv} way are still ${t}. Write it in ${t}'s own writing system, word for word, never corrected.`,
    `"native": they spoke ${nv} — real ${nv} words and grammar, the way they would talk to another ${nv} speaker. A learner who is stuck often does this. Write exactly what they said, in ${nv}'s own writing system. Never translate it into ${t}.`,
    `If most of it is ${t} with one or two ${nv} words inside, it is "target": write the ${t} words in ${t} and the ${nv} word in ${nv}.`,
    `"none": only hesitation sounds (uh, um, 어, 음) or no words at all; text is empty.`,
    `Only write words you actually hear. Never invent a sentence to fill unclear audio.`,
  ].join("\n")
}

/** The utterance as the learner said it — "" when the audio holds no words
 *  (only a hesitation), null when the re-read could not be made (no audio,
 *  timeout, error). With `native`, the line is classified and written in
 *  the language actually spoken; without it (an app build that doesn't send
 *  one), always the target language, as before. */
export async function rereadUtterance(
  apiKey: string,
  model: string,
  language: string,
  audio: ArrayBuffer[],
  native: string | null = null,
  timeoutMs = 4000,
): Promise<{ text: string; spoken: Spoken } | null> {
  const bytes = audio.reduce((n, c) => n + c.byteLength, 0)
  if (bytes < 16000 * 2 * 0.3) return null   // under 0.3 s: nothing to read
  const name = languageName(language)
  const audioPart = { inlineData: { mimeType: "audio/wav", data: base64Encode(wav(audio)) } }
  const body = JSON.stringify(native ? {
    systemInstruction: { parts: [{ text: classifyingSystem(language, native) }] },
    contents: [{ role: "user", parts: [audioPart, { text: "Classify and transcribe this utterance." }] }],
    generationConfig: {
      maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" },
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          language: { type: "STRING", enum: ["target", "native", "none"] },
          text: { type: "STRING" },
        },
        required: ["language", "text"],
        propertyOrdering: ["language", "text"],
      },
    },
  } : {
    systemInstruction: { parts: [{ text: [
      languagePin(language),
      `The audio may begin or end with silence or a little of another voice; transcribe only the learner's ${name}.`,
      `Reply with the transcript alone, in ${name} and in ${name}'s own writing system — no quotes, no notes. If the audio holds only hesitation sounds or no words at all, reply with nothing.`,
    ].join("\n") }] },
    contents: [{ role: "user", parts: [audioPart, { text: `Transcribe this ${name}.` }] }],
    generationConfig: { maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" } },
  })
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetch(
      `${API_HOST}/v1beta/models/${model}:generateContent?key=${apiKey}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body, signal: controller.signal },
    )
    if (!res.ok) return null
    const json = await res.json() as {
      candidates?: { content?: { parts?: { text?: string; thought?: boolean }[] } }[]
    }
    const parts = json.candidates?.[0]?.content?.parts ?? []
    const raw = parts.filter((p) => !p.thought).map((p) => p.text ?? "").join("").trim()
    if (!native) return { text: raw, spoken: raw === "" ? "none" : "target" }
    const parsed = JSON.parse(raw) as { language?: string; text?: string }
    const text = (parsed.text ?? "").trim()
    const spoken: Spoken = parsed.language === "native" ? "native"
      : parsed.language === "target" ? "target" : "none"
    return { text: spoken === "none" ? "" : text, spoken: text === "" ? "none" : spoken }
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}
