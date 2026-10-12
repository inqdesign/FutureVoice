// Cartesia — the clone voice's second home (2026-10-12).
//
// Why: ElevenLabs Pro holds 160 custom voices and 290 voice creations a
// month for the whole account, and both were ~80% used with ~25 signups a
// week; Cartesia stores instant clones without a limit (support, 2026-10-12)
// at the same price per character ($37–39 vs $40 / 1M), measured faster
// (first audio 100 ms vs 148 ms, gateway/test/probe-tts-ttfb.mjs) and
// preferred by ear by the founder.
//
// How a voice is routed: by the SHAPE of its id. Cartesia ids are UUIDs,
// ElevenLabs ids are 20 alphanumerics — so every path (this edge function,
// the gateway, an old app build that just passes the id along) can tell
// where a voice lives without a database read. The id is stored in
// `voice_clones.elevenlabs_voice_id` like any other (the column name is
// history; it means "the provider's voice id").

const HOST = "https://api.cartesia.ai"
export const CARTESIA_VERSION = "2026-08-14"
export const CARTESIA_MODEL = "sonic-3.6"

// `<uuid>` or `<uuid>:<accent>` — the accent rides IN the id (2026-10-12).
// Picking an accent must hand the app a NEW voice id: every build ignores a
// "saved" accent whose id equals the live voice (AppState.adoptRemixedVoice
// returns early), so the pick would never stick. One Cartesia voice speaks
// every accent it has been given, so "<uuid>:british" is the same voice told
// to speak British — the server and gateway read the accent straight off the
// id, and deleting an old id never deletes a voice another id still uses.
const VOICE = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?::([a-z-]+))?$/i

export function isCartesiaVoice(voiceId: string | null | undefined): boolean {
  return !!voiceId && VOICE.test(voiceId)
}

/** The Cartesia voice and the accent an id carries. */
export function parseVoice(voiceId: string): { uuid: string; accent: string | null } {
  const m = VOICE.exec(voiceId)
  return m ? { uuid: m[1].toLowerCase(), accent: m[2] ? m[2].toLowerCase() : null } : { uuid: voiceId, accent: null }
}

/** Each accent's language — an accent is applied only to a line in it. */
export const ACCENT_LANGUAGE: Record<string, string> = {
  "general-american": "en", "british": "en", "australian": "en", "indian-english": "en", "southern-us": "en",
  "standard-german": "de", "standard-japanese": "ja", "korean": "ko",
}

/** A voice's own accent, required before others can be added. */
const BASE_ACCENT: Record<string, string> = {
  en: "general-american", de: "standard-german", ja: "standard-japanese", ko: "korean",
}

/** The app's accent picks arrive as ElevenLabs remix PROMPTS
 *  (VoiceAccentCatalog) — read the accent out of the wording. */
export function accentFromDescription(description: string): string | null {
  const d = description.toLowerCase()
  if (d.includes("general american") || d.includes("american english")) return "general-american"
  if (d.includes("british")) return "british"
  if (d.includes("australian")) return "australian"
  if (d.includes("standard german") || d.includes("hochdeutsch")) return "standard-german"
  if (d.includes("japanese")) return "standard-japanese"
  if (d.includes("korean")) return "korean"
  return null
}

/** Make sure the voice can speak `accent`: a voice with no accent of its own
 *  gets its language's base first (Cartesia requires one), then the accent
 *  is added if missing (~225 credits, once per voice per accent). */
export async function ensureAccent(uuid: string, accent: string): Promise<{ ok: boolean; detail?: string }> {
  const r = await fetch(`${HOST}/voices/${uuid}`, { headers: headers(false) })
  if (!r.ok) return { ok: false, detail: `get voice ${r.status}` }
  const v = await r.json() as { language?: string; accents?: { accent: string }[] | null }
  let have = (v.accents ?? []).map((a) => a.accent)
  if (have.length === 0) {
    const base = BASE_ACCENT[(v.language ?? "en").split("-")[0]] ?? "general-american"
    const p = await fetch(`${HOST}/voices/${uuid}`, {
      method: "PATCH", headers: headers(), body: JSON.stringify({ accent: base }),
    })
    if (!p.ok) return { ok: false, detail: `set base ${p.status} ${(await p.text()).slice(0, 200)}` }
    have = [base]
  }
  if (have.includes(accent)) return { ok: true }
  const a = await fetch(`${HOST}/voices/${uuid}/accents`, {
    method: "PATCH", headers: headers(), body: JSON.stringify({ accents: [accent] }),
  })
  if (!a.ok) return { ok: false, detail: `add accent ${a.status} ${(await a.text()).slice(0, 200)}` }
  return { ok: true }
}

/** Who clones on Cartesia: `CLONE_PROVIDER` = "elevenlabs" (default, nobody),
 *  "cartesia" (everyone), or a comma-separated list of user ids — so the
 *  founder's accounts go first and a bad day is one secret away from undone. */
export function clonesOnCartesia(userId: string): boolean {
  const v = (Deno.env.get("CLONE_PROVIDER") ?? "").trim().toLowerCase()
  if (!v || v === "elevenlabs") return false
  if (v === "cartesia") return true
  return v.split(",").map((s) => s.trim()).includes(userId.toLowerCase())
}

function headers(json = true): Record<string, string> {
  const key = Deno.env.get("CARTESIA_API_KEY") ?? ""
  return {
    "Authorization": `Bearer ${key}`,
    "Cartesia-Version": CARTESIA_VERSION,
    ...(json ? { "Content-Type": "application/json" } : {}),
  }
}

/** The languages a clone may speak. Cartesia reads a line in whatever
 *  language it is TOLD (measured: German without `language` came out in the
 *  clone's own English), so every request names one. */
const SUPPORTED = new Set(["en", "de", "ja", "ko", "fr", "es", "pt", "it", "nl", "zh", "hi", "pl", "ru", "sv", "tr"])

/** The language a line is in. The script decides where it can (Hangul,
 *  kana); otherwise the learner's target language, which is what every line
 *  the clone speaks is written in. */
export function lineLanguage(text: string, target: string | null | undefined): string {
  if (/[가-힣ᄀ-ᇿ㄰-㆏]/.test(text)) return "ko"
  if (/[぀-ヿ]/.test(text)) return "ja"
  const t = (target ?? "").toLowerCase().split("-")[0]
  return SUPPORTED.has(t) ? t : "en"
}

/** ElevenLabs' speed knob (0.7–1.2, 1 = as recorded) maps onto Cartesia's
 *  (0.6–1.5, 1 = normal) one to one inside the range we use. */
function speedConfig(speed: number | undefined): Record<string, unknown> {
  return typeof speed === "number" && speed >= 0.6 && speed <= 1.5
    ? { generation_config: { speed } } : {}
}

/** The voice and accent fields of a request for one line. */
function voiceFields(voiceId: string, language: string): Record<string, unknown> {
  const { uuid, accent } = parseVoice(voiceId)
  return {
    voice: { mode: "id", id: uuid },
    language,
    ...(accent && ACCENT_LANGUAGE[accent] === language ? { accent } : {}),
  }
}

export interface CartesiaLine {
  voiceId: string
  text: string
  language: string
  speed?: number
}

/** Whole line as MP3 — the buffered path. */
export function synthesizeMp3(line: CartesiaLine): Promise<Response> {
  return fetch(`${HOST}/tts/bytes`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model_id: CARTESIA_MODEL,
      transcript: line.text,
      ...voiceFields(line.voiceId, line.language),
      output_format: { container: "mp3", sample_rate: 44100, bit_rate: 128000 },
      ...speedConfig(line.speed),
    }),
  })
}

/** Raw 16-bit LE mono PCM, streamed as it is made — the app's streaming
 *  path (`X-Audio-Format: pcm_<rate>`). */
export function synthesizePcmStream(line: CartesiaLine, sampleRate: number): Promise<Response> {
  return fetch(`${HOST}/tts/bytes`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model_id: CARTESIA_MODEL,
      transcript: line.text,
      ...voiceFields(line.voiceId, line.language),
      output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: sampleRate },
      ...speedConfig(line.speed),
    }),
  })
}

/** The line with word timings, shaped like ElevenLabs' `/with-timestamps`
 *  reply ({audio_base64, alignment{characters, …_start/_end_times}}) so every
 *  app build reads it unchanged. Cartesia times WORDS; each word's window is
 *  spread over its characters and the gaps between words become the spaces —
 *  the app groups characters back into words, so nothing finer is needed.
 *  The audio is WAV: this endpoint streams raw PCM only, and every player
 *  in the app opens a WAV as readily as an MP3 (it already stores some). */
export async function synthesizeWithTimestamps(line: CartesiaLine): Promise<
  { ok: true; json: Record<string, unknown> } | { ok: false; status: number; detail: string }
> {
  const sampleRate = 44100
  const r = await fetch(`${HOST}/tts/sse`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model_id: CARTESIA_MODEL,
      transcript: line.text,
      ...voiceFields(line.voiceId, line.language),
      add_timestamps: true,
      output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: sampleRate },
      ...speedConfig(line.speed),
    }),
  })
  if (!r.ok || !r.body) return { ok: false, status: r.status, detail: (await r.text()).slice(0, 500) }

  const chunks: Uint8Array[] = []
  const words: string[] = []
  const starts: number[] = []
  const ends: number[] = []
  const reader = r.body.pipeThrough(new TextDecoderStream()).getReader()
  let buf = ""
  for (;;) {
    const { value, done } = await reader.read()
    if (done) break
    buf += value
    let nl: number
    while ((nl = buf.indexOf("\n")) >= 0) {
      const lineText = buf.slice(0, nl).trim()
      buf = buf.slice(nl + 1)
      if (!lineText.startsWith("data:")) continue
      let m: any
      try { m = JSON.parse(lineText.slice(5)) } catch { continue }
      if (m.type === "error") return { ok: false, status: 502, detail: String(m.message ?? m.title ?? "cartesia error") }
      if (m.type === "chunk" && typeof m.data === "string") chunks.push(base64ToBytes(m.data))
      if (m.type === "timestamps" && m.word_timestamps) {
        words.push(...m.word_timestamps.words)
        starts.push(...m.word_timestamps.start)
        ends.push(...m.word_timestamps.end)
      }
    }
  }
  const pcm = concat(chunks)
  const wav = wavBytes(pcm, sampleRate)
  return {
    ok: true,
    json: {
      audio_base64: bytesToBase64(wav),
      alignment: characterAlignment(line.text, words, starts, ends),
    },
  }
}

/** Spread word windows over the characters of the line as the app sent it.
 *  Words are found in the text in order; anything between them (spaces,
 *  punctuation Cartesia didn't count as a word) takes the gap's times. A word
 *  that can't be found is skipped — the app's own check (`alignmentMatches`)
 *  then discards timings that don't spell the line, and falls back to its
 *  estimate, which is exactly what it does with any doubtful alignment. */
export function characterAlignment(text: string, words: string[], starts: number[], ends: number[]) {
  const chars = Array.from(text)
  const characters: string[] = []
  const s: number[] = []
  const e: number[] = []
  const push = (c: string, a: number, b: number) => { characters.push(c); s.push(a); e.push(b) }
  let pos = 0
  let lastEnd = 0
  for (let i = 0; i < words.length; i++) {
    const w = Array.from(words[i])
    const at = findFrom(chars, w, pos)
    if (at < 0 || w.length === 0) continue
    for (; pos < at; pos++) push(chars[pos], lastEnd, starts[i])
    const span = (ends[i] - starts[i]) / w.length
    for (let k = 0; k < w.length; k++, pos++) push(chars[pos], starts[i] + span * k, starts[i] + span * (k + 1))
    lastEnd = ends[i]
  }
  for (; pos < chars.length; pos++) push(chars[pos], lastEnd, lastEnd)
  return { characters, character_start_times_seconds: s, character_end_times_seconds: e }
}

function findFrom(hay: string[], needle: string[], from: number): number {
  outer: for (let i = from; i + needle.length <= hay.length; i++) {
    for (let k = 0; k < needle.length; k++) if (hay[i + k] !== needle[k]) continue outer
    return i
  }
  return -1
}

/** Instant clone from the learner's recording. `language` is the language
 *  the recording is read in. Returns the new voice id. */
export async function cloneVoice(
  clip: File, name: string, language: string,
): Promise<{ ok: true; voiceId: string } | { ok: false; status: number; detail: string }> {
  const form = new FormData()
  form.append("clip", clip, clip.name || "sample.wav")
  form.append("name", name.slice(0, 100) || "voice")
  form.append("language", SUPPORTED.has(language) ? language : "en")
  const r = await fetch(`${HOST}/voices/clone`, { method: "POST", headers: headers(false), body: form })
  if (!r.ok) return { ok: false, status: r.status, detail: (await r.text()).slice(0, 500) }
  const json = await r.json() as { id?: string }
  if (!json.id) return { ok: false, status: 502, detail: "cartesia clone returned no id" }
  return { ok: true, voiceId: json.id }
}

/** Delete a clone. A voice that is already gone counts as deleted. */
export async function deleteVoice(voiceId: string): Promise<{ ok: boolean; status: number; detail?: string }> {
  const r = await fetch(`${HOST}/voices/${parseVoice(voiceId).uuid}`, { method: "DELETE", headers: headers(false) })
  if (r.ok || r.status === 404) return { ok: true, status: r.status }
  return { ok: false, status: r.status, detail: (await r.text()).slice(0, 300) }
}

/** Rename a clone. */
export async function renameVoice(voiceId: string, name: string): Promise<{ ok: boolean; status: number; detail?: string }> {
  const r = await fetch(`${HOST}/voices/${parseVoice(voiceId).uuid}`, {
    method: "PATCH", headers: headers(), body: JSON.stringify({ name: name.slice(0, 100) }),
  })
  if (r.ok) return { ok: true, status: r.status }
  return { ok: false, status: r.status, detail: (await r.text()).slice(0, 300) }
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

function bytesToBase64(bytes: Uint8Array): string {
  let bin = ""
  const step = 0x8000
  for (let i = 0; i < bytes.length; i += step) {
    bin += String.fromCharCode(...bytes.subarray(i, i + step))
  }
  return btoa(bin)
}

function concat(parts: Uint8Array[]): Uint8Array {
  const n = parts.reduce((a, p) => a + p.length, 0)
  const out = new Uint8Array(n)
  let o = 0
  for (const p of parts) { out.set(p, o); o += p.length }
  return out
}

/** 16-bit mono PCM → WAV. */
export function wavBytes(pcm: Uint8Array, sampleRate: number): Uint8Array {
  const out = new Uint8Array(44 + pcm.length)
  const v = new DataView(out.buffer)
  const ascii = (o: number, s: string) => { for (let i = 0; i < s.length; i++) out[o + i] = s.charCodeAt(i) }
  ascii(0, "RIFF"); v.setUint32(4, 36 + pcm.length, true); ascii(8, "WAVE")
  ascii(12, "fmt "); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true)
  v.setUint32(24, sampleRate, true); v.setUint32(28, sampleRate * 2, true)
  v.setUint16(32, 2, true); v.setUint16(34, 16, true)
  ascii(36, "data"); v.setUint32(40, pcm.length, true)
  out.set(pcm, 44)
  return out
}
