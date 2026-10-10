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

import { base64Encode, languageName } from "./transcriber"

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
export type Spoken = "target" | "native" | "other" | "none"

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

/** The classifying prompt for an app that did NOT say which language the
 *  learner speaks (every build before 1.1.5). The old "write <target> only"
 *  prompt invented a target sentence for a Korean line the live model had
 *  written in Devanagari ("हम दो आए हैं" → "drohen kann", 2026-10-09).
 *  "other" is any language but the target; `CallSession` names it from the
 *  script the re-read wrote it in. Must stay byte-identical to
 *  test/probe-reread-unknown.mjs `unknownSystem` — that probe is its
 *  measurement: another-language lines written as a target sentence 72/76
 *  (old) → 2/76; Hangul-read German with a heavy accent labelled "other"
 *  7/68, which the script rule mostly sends back to the target or to a
 *  kept-as-said native line. */
export function unknownNativeSystem(target: string): string {
  const t = languageName(target)
  return [
    `You hear one utterance from someone learning ${t}, in the middle of a ${t} conversation. Their own language is not known. Decide which language they actually SPOKE, then transcribe it.`,
    `"target": they spoke ${t} — however strong the accent, however broken the grammar, however much it sounds like another language. Words of ${t} pronounced with a foreign accent are still ${t}. Write it in ${t}'s own writing system, word for word, never corrected.`,
    `"other": they spoke a different language — real words and grammar of that language, the way they would talk to someone who speaks it. A learner who is stuck often switches to their own language. Write exactly what they said, in that language's own writing system. Never translate it into ${t}.`,
    `If most of it is ${t} with one or two words of another language inside, it is "target": write the ${t} words in ${t} and the other word as said.`,
    `"none": only hesitation sounds (uh, um, 어, 음, अ) or no words at all; text is empty.`,
    `Only write words you actually hear. Never invent a sentence to fill unclear audio.`,
  ].join("\n")
}

/** The utterance as the learner said it — "" when the audio holds no words
 *  (only a hesitation), null when the re-read could not be made (no audio,
 *  timeout, error). With `native`, the line is classified and written in
 *  the language actually spoken; without it (an app build that doesn't send
 *  one), classified as target / other / none (`unknownNativeSystem`). */
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
  const audioPart = { inlineData: { mimeType: "audio/wav", data: base64Encode(wav(audio)) } }
  const body = JSON.stringify({
    systemInstruction: { parts: [{ text: native
      ? classifyingSystem(language, native) : unknownNativeSystem(language) }] },
    contents: [{ role: "user", parts: [audioPart, { text: "Classify and transcribe this utterance." }] }],
    generationConfig: {
      maxOutputTokens: 400, thinkingConfig: { thinkingLevel: "minimal" },
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          language: { type: "STRING", enum: native ? ["target", "native", "none"] : ["target", "other", "none"] },
          text: { type: "STRING" },
        },
        required: ["language", "text"],
        propertyOrdering: ["language", "text"],
      },
    },
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
    const parsed = JSON.parse(raw) as { language?: string; text?: string }
    const text = (parsed.text ?? "").trim()
    const spoken: Spoken = parsed.language === "native" ? "native"
      : parsed.language === "other" ? "other"
      : parsed.language === "target" ? "target" : "none"
    return { text: spoken === "none" ? "" : text, spoken: text === "" ? "none" : spoken }
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}
