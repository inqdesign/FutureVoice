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
  "mexican": "es", "castilian": "es",
}

/** A voice's own accent, required before others can be added — deliberately
 *  one the app never OFFERS. Cartesia treats the base as "already this
 *  accent", so a pick equal to it changes nothing: with "general-american" as
 *  the base, choosing American played the recording as it was (2026-10-12,
 *  first device test). With an off-menu base every pick is a real accent.
 *  ja/ko have one accent each and no picker. */
const BASE_ACCENT: Record<string, string> = {
  en: "new-zealand", de: "austrian-german", ja: "standard-japanese", ko: "korean",
  es: "united-states-spanish",
}

/** The app's accent picks arrive as ElevenLabs remix PROMPTS
 *  (VoiceAccentCatalog) — read the accent out of the wording. */
export function accentFromDescription(description: string): string | null {
  const d = description.toLowerCase()
  if (d.includes("general american") || d.includes("american english")) return "general-american"
  if (d.includes("british")) return "british"
  if (d.includes("australian")) return "australian"
  if (d.includes("standard german") || d.includes("hochdeutsch")) return "standard-german"
  if (d.includes("mexican spanish")) return "mexican"
  if (d.includes("castilian spanish")) return "castilian"
  if (d.includes("japanese")) return "standard-japanese"
  if (d.includes("korean")) return "korean"
  return null
}

/** The accent every German line is spoken in unless the voice id names
 *  another German one (2026-10-13, founder: learning German means standard
 *  German by default, also after switching to it from another language).
 *  The id carries ONE accent, usually the English one, so this is decided
 *  per line rather than stored. */
export const GERMAN_DEFAULT = "standard-german"

/** The same rule for every language that has one: the accent a line in it
 *  is spoken in unless the id names another of that language. Spanish
 *  (2026-10-15) defaults to Mexican, the app's first Spanish option. */
export const LANGUAGE_DEFAULT_ACCENT: Record<string, string> = {
  de: GERMAN_DEFAULT,
  es: "mexican",
}

/** Per isolate: does voice `uuid` carry `accent` (`<uuid>:<accent>`)? */
const accentReady = new Map<string, boolean>()

/** Whether the voice can speak `accent`, adding it if it can't yet. Only a
 *  YES is cached: a failed add is tried again on the next line, because the
 *  plain fallback is not neutral — a German clone's base accent is Austrian
 *  (BASE_ACCENT), and every German learner is to hear standard German
 *  (founder, 2026-10-14). */
async function hasAccent(uuid: string, accent: string): Promise<boolean> {
  const key = `${uuid}:${accent}`
  if (accentReady.get(key)) return true
  if (await isStockVoice(uuid)) return false
  const r = await ensureAccent(uuid, accent)
  if (r.ok) accentReady.set(key, true)
  else console.warn("accent not on voice", key, r.detail)
  return r.ok
}

/** The line with its accent made SAFE to send, and the German default
 *  applied. A request naming an accent the voice lacks fails outright, so an
 *  accent is only sent once the voice is known to carry it (added here if it
 *  doesn't). That covers the accent the id itself names too: a voice moved
 *  to Cartesia was saved as `<uuid>:standard-german` while the background
 *  add of that accent had failed, and every line it spoke — the greeting,
 *  the whole call — was refused with "this voice does not support accent
 *  'standard-german'" (2026-10-13/14). Never throws: any doubt speaks the
 *  line plain. Spanish lines get the same default treatment as German
 *  (`LANGUAGE_DEFAULT_ACCENT`). */
export async function withDefaultAccent(line: CartesiaLine): Promise<CartesiaLine> {
  const { uuid, accent } = parseVoice(line.voiceId)
  try {
    if (accent && ACCENT_LANGUAGE[accent] === line.language) {
      return (await hasAccent(uuid, accent)) ? line : { ...line, voiceId: uuid }
    }
    const fallback = LANGUAGE_DEFAULT_ACCENT[line.language]
    if (!fallback) return line
    return (await hasAccent(uuid, fallback))
      ? { ...line, voiceId: `${uuid}:${fallback}` } : { ...line, voiceId: uuid }
  } catch {
    return { ...line, voiceId: uuid }
  }
}

/** Make sure the voice can speak `accent`: a voice with no accent of its own
 *  gets its language's base first (Cartesia requires one), then the accent
 *  is added if missing (~225 credits, once per voice per accent). */
export async function ensureAccent(uuid: string, accent: string): Promise<{ ok: boolean; detail?: string }> {
  const r = await fetch(`${HOST}/voices/${uuid}`, { headers: headers(false) })
  if (!r.ok) return { ok: false, detail: `get voice ${r.status}` }
  const v = await r.json() as { language?: string; accents?: { accent: string; is_native?: boolean }[] | null }
  let have = (v.accents ?? []).map((a) => a.accent)
  const base = BASE_ACCENT[(v.language ?? "en").split("-")[0]] ?? "new-zealand"
  const native = (v.accents ?? []).find((a) => a.is_native)?.accent
  // No base yet, or the base IS the accent asked for (voices made before the
  // off-menu base): set the off-menu base. The old base stays on the voice as
  // an added accent, so it is now a real change.
  // A voice can also come back WITH accents but none marked native
  // (2026-10-13, Android QA): adding one then fails with "Voice has no
  // native accent set", so it gets the base too — only when the accent
  // asked for isn't already on it, the one case that could not succeed.
  if (have.length === 0 || (native === accent && base !== accent) ||
      (!native && !have.includes(accent))) {
    const p = await fetch(`${HOST}/voices/${uuid}`, {
      method: "PATCH", headers: headers(), body: JSON.stringify({ accent: base }),
    })
    if (!p.ok) return { ok: false, detail: `set base ${p.status} ${(await p.text()).slice(0, 200)}` }
    if (!have.includes(base)) have = [base, ...have]
  }
  if (have.includes(accent)) return { ok: true }
  const add = () => fetch(`${HOST}/voices/${uuid}/accents`, {
    method: "PATCH", headers: headers(), body: JSON.stringify({ accents: [accent] }),
  })
  let a = await add()
  // Two accents added to a new voice at once (the clone's German default and
  // the learner's pick, 2026-10-13) race on the base: one finds no native
  // accent set yet and is refused. Set the base and try once more.
  if (a.status === 400) {
    await a.text()
    await new Promise((r) => setTimeout(r, 800))
    await fetch(`${HOST}/voices/${uuid}`, { method: "PATCH", headers: headers(), body: JSON.stringify({ accent: base }) })
    a = await add()
  }
  // 409: the same accent is being added by someone else right now — the
  // clone's own background German add racing voice-move-all's (2026-10-14).
  // It is not a refusal; wait for it to land.
  if (a.status === 409) {
    const detail = (await a.text()).slice(0, 200)
    for (let i = 0; i < 6; i++) {
      await new Promise((r) => setTimeout(r, 1500))
      const g = await fetch(`${HOST}/voices/${uuid}`, { headers: headers(false) })
      if (!g.ok) continue
      const now = await g.json() as { accents?: { accent: string }[] | null }
      if ((now.accents ?? []).some((x) => x.accent === accent)) return { ok: true }
    }
    return { ok: false, detail: `add accent 409 ${detail}` }
  }
  if (!a.ok) return { ok: false, detail: `add accent ${a.status} ${(await a.text()).slice(0, 200)}` }
  return { ok: true }
}

/** Cartesia's own library voices — the voices the Find-people people and a
 *  learner's public profile speak with (2026-10-12) — may be used by anyone.
 *  A clone is ours (`is_owner`), so this can never open another learner's
 *  voice: only a voice Cartesia publishes to everyone passes. Answers are
 *  cached per isolate; a voice's ownership never changes. */
const stockAnswers = new Map<string, boolean>()
export async function isStockVoice(voiceId: string): Promise<boolean> {
  if (!isCartesiaVoice(voiceId) || voiceId.includes(":")) return false
  const cached = stockAnswers.get(voiceId)
  if (cached !== undefined) return cached
  try {
    const r = await fetch(`${HOST}/voices/${voiceId}`, { headers: headers(false) })
    if (!r.ok) return false
    const v = await r.json() as { is_owner?: boolean; is_public?: boolean }
    const stock = v.is_owner === false
    stockAnswers.set(voiceId, stock)
    return stock
  } catch {
    return false
  }
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

/** The app's speed rungs (ElevenLabs' scale: Slow 0.85 · Relaxed 0.9 ·
 *  Normal 1.0) onto Cartesia's. Measured 2026-10-12 on the same lines:
 *  Cartesia at 1.0 speaks 15–35% slower than ElevenLabs at 1.0, and its knob
 *  is weak — 1.0 → 1.5 is only 6–12% faster. So the rungs are stretched over
 *  Cartesia's whole upper range: Slow → 1.0, Relaxed → ~1.17, Normal → 1.5
 *  (where English matches ElevenLabs' Relaxed pace; Japanese stays ~20%
 *  slower). Absent = ElevenLabs' default, 1.0. */
export function cartesiaSpeed(speed: number | undefined): number {
  const s = typeof speed === "number" && speed >= 0.6 && speed <= 1.5 ? speed : 1.0
  return Math.max(0.6, Math.min(1.5, 1.0 + (s - 0.85) / 0.15 * 0.5))
}

/** Every line is generated with `emotion: "neutral"` — preferred by ear on
 *  Cartesia's playground (founder, 2026-10-12): without it the model reads
 *  emotion into each line, and the voice sounded less like the speaker. */
export const EMOTION = "neutral"

function speedConfig(speed: number | undefined): Record<string, unknown> {
  return { generation_config: { speed: cartesiaSpeed(speed), emotion: EMOTION } }
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
  // Cartesia's clone speaks at the LOUDNESS of its recording — measured
  // 2026-10-12: a -37.8 LUFS take gave a -36.4 LUFS voice, the same take
  // levelled to -20 gave -19.8. Phone takes are quiet, and the un-accented
  // voice came out so soft the app's own levelling couldn't lift the first
  // greeting. So the take is levelled here before it goes up.
  // The room is taken out on the PHONE since 2026-10-15 (DeepFilterNet,
  // `VoiceDenoiser` / Android's twin): ElevenLabs Audio Isolation did it
  // here before, and ElevenLabs is gone. An older build's take arrives as
  // recorded and is cloned as recorded.
  const levelled = await levelledWav(clip)
  form.append("clip", levelled ?? clip, clip.name || "sample.wav")
  form.append("name", name.slice(0, 100) || "voice")
  form.append("language", SUPPORTED.has(language) ? language : "en")
  const r = await fetch(`${HOST}/voices/clone`, { method: "POST", headers: headers(false), body: form })
  if (!r.ok) return { ok: false, status: r.status, detail: (await r.text()).slice(0, 500) }
  const json = await r.json() as { id?: string }
  if (!json.id) return { ok: false, status: 502, detail: "cartesia clone returned no id" }
  // Every clone can speak standard German from the start (GERMAN_DEFAULT);
  // best-effort and off the clone's own wait (three round trips);
  // withDefaultAccent adds it later if this fails.
  const voiceId = json.id
  const addGerman = ensureAccent(voiceId, GERMAN_DEFAULT)
    .then((de) => { if (de.ok) accentReady.set(`${voiceId}:${GERMAN_DEFAULT}`, true); else console.warn("german accent at clone failed", de.detail) })
    .catch((e) => console.warn("german accent at clone failed", String(e)))
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime
  if (runtime?.waitUntil) runtime.waitUntil(addGerman)
  else await addGerman
  return { ok: true, voiceId }
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

/** Float channels (an MP3 decoded on the server) → a 16-bit mono WAV File,
 *  so it goes through the same levelling as a phone take. */
export function wavFileFromFloat(channels: Float32Array[], sampleRate: number, name = "sample.wav"): File {
  const n = channels[0]?.length ?? 0
  const pcm = new Int16Array(n)
  for (let i = 0; i < n; i++) {
    let v = 0
    for (const ch of channels) v += ch[i]
    v /= Math.max(1, channels.length)
    pcm[i] = Math.max(-32768, Math.min(32767, Math.round(v * 32767)))
  }
  return new File([wavBytes(new Uint8Array(pcm.buffer), sampleRate).buffer as ArrayBuffer], name, { type: "audio/wav" })
}

/** A 16-bit PCM WAV with its speech brought to ~-20 dBFS RMS (boost only,
 *  ≤30 dB), peaks held under full scale by a soft knee above 0.7. Anything
 *  that isn't a plain 16-bit PCM WAV is returned as null (sent unchanged). */
export async function levelledWav(file: File): Promise<File | null> {
  try {
    const buf = new Uint8Array(await file.arrayBuffer())
    const v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
    const tag = (o: number) => String.fromCharCode(buf[o], buf[o + 1], buf[o + 2], buf[o + 3])
    if (buf.length < 44 || tag(0) !== "RIFF" || tag(8) !== "WAVE") return null
    let o = 12, fmtOk = false, rate = 0, dataOff = -1, dataLen = 0, channels = 1
    while (o + 8 <= buf.length) {
      const id = tag(o), len = v.getUint32(o + 4, true)
      if (id === "fmt ") {
        fmtOk = v.getUint16(o + 8, true) === 1 && v.getUint16(o + 22, true) === 16
        channels = v.getUint16(o + 10, true)
        rate = v.getUint32(o + 12, true)
      } else if (id === "data") { dataOff = o + 8; dataLen = Math.min(len, buf.length - o - 8); break }
      o += 8 + len + (len % 2)
    }
    if (!fmtOk || dataOff < 0 || rate <= 0) return null
    const n = Math.floor(dataLen / 2)
    const samples = new Int16Array(buf.buffer.slice(buf.byteOffset + dataOff, buf.byteOffset + dataOff + n * 2))
    // Speech RMS: 20 ms blocks within 30 dB of the loudest block.
    const block = Math.max(1, Math.floor(rate * channels * 0.02))
    const rms: number[] = []
    for (let i = 0; i + block <= samples.length; i += block) {
      let sum = 0
      for (let k = i; k < i + block; k++) sum += (samples[k] / 32768) ** 2
      rms.push(Math.sqrt(sum / block))
    }
    const loudest = Math.max(...rms, 1e-9)
    const voiced = rms.filter((r) => r > loudest * 0.0316 && r > 1e-4)
    if (voiced.length === 0) return null
    const speech = Math.sqrt(voiced.reduce((a, r) => a + r * r, 0) / voiced.length)
    const gain = Math.min(Math.max(10 ** (-20 / 20) / speech, 1), 10 ** (30 / 20))
    if (gain < 1.12) return null   // already within 1 dB of the target
    const knee = 0.7, room = 0.985 - knee
    for (let i = 0; i < samples.length; i++) {
      let y = (samples[i] / 32768) * gain
      const a = Math.abs(y)
      if (a > knee) y = Math.sign(y) * (knee + room * Math.tanh((a - knee) / room))
      samples[i] = Math.round(y * 32767)
    }
    const out = new Uint8Array(buf)
    out.set(new Uint8Array(samples.buffer), dataOff)
    return new File([out], file.name || "sample.wav", { type: "audio/wav" })
  } catch {
    return null
  }
}
