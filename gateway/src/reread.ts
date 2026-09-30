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

/** The utterance as the learner said it, in the target language — "" when
 *  the audio holds no words (only a hesitation), null when the re-read
 *  could not be made (no audio, timeout, error). */
export async function rereadUtterance(
  apiKey: string,
  model: string,
  language: string,
  audio: ArrayBuffer[],
  timeoutMs = 4000,
): Promise<string | null> {
  const bytes = audio.reduce((n, c) => n + c.byteLength, 0)
  if (bytes < 16000 * 2 * 0.3) return null   // under 0.3 s: nothing to read
  const name = languageName(language)
  const system = [
    languagePin(language),
    `The audio may begin or end with silence or a little of another voice; transcribe only the learner's ${name}.`,
    `Reply with the transcript alone, in ${name} and in ${name}'s own writing system — no quotes, no notes. If the audio holds only hesitation sounds or no words at all, reply with nothing.`,
  ].join("\n")
  const body = JSON.stringify({
    systemInstruction: { parts: [{ text: system }] },
    contents: [{
      role: "user",
      parts: [
        { inlineData: { mimeType: "audio/wav", data: base64Encode(wav(audio)) } },
        { text: `Transcribe this ${name}.` },
      ],
    }],
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
    return parts.filter((p) => !p.thought).map((p) => p.text ?? "").join("").trim()
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}
