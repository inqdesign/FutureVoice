// A native reference reading of a speech script, in a male and a female
// voice, with every word timed — what Season 2's speech score compares a
// take with (2026-11-08, founder: "make a reference speech and judge against
// it").
//
// Why a reference: Azure's own scores can't tell a fluent learner from a
// native reader (both near the top), and fixed thresholds can't tell a
// narrator's held word from a learner's hesitation. Compared word for word
// with a native reading of the SAME text, three things separate human
// narrators, ordinary natives and learners and agree with expert ratings
// (speechocean762, Spearman ~0.8): speaking speed, the word-length pattern
// (rhythm), and pauses where the native reading has none. Intonation and
// stress compared this way did NOT separate humans, so they aren't used.
//
// The reference is gender-matched (founder: not everyone has a cloned voice,
// and a reference per user doesn't scale). Its words are timed the way the
// calibration timed them: Azure pronunciation assessment (en-US) on <=25 s
// windows cut at silences, against the whole script. Cartesia's own word
// timestamps were checked against that on the same audio and disagree
// (zero-length words, 33 pauses where Azure finds 13), so they aren't used.
//
// Cached by (version, language, gender, voice, text): a challenge's reference
// is made once, by whoever opens it first. Free to the learner; the cost is
// ~2 x 60 s of TTS and assessment per script.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse, serviceRoleClient } from "../_shared/credits.ts"
import { CARTESIA_MODEL, CARTESIA_VERSION, wavBytes } from "../_shared/cartesia.ts"

const SOURCE_FN = "speech-reference"
const VERSION = 1
const DAILY_CAP = 40            // generations (cache misses) per learner per day
const MAX_CHARS = 3_000
const RATE = 16_000
const WINDOW_SECONDS = 25

/** The English preset voices measured in the calibration. */
const VOICES: Record<string, Record<"male" | "female", string>> = {
  en: { male: "c961b81c-a935-4c17-bfb3-ba2239de8c2f", female: "999df508-4de5-40a7-8bd3-8c12f678c284" },
}

/** A word and its times in ms; `ph` (listening audio only, 2026-11-13) is
 *  each of its sounds with Azure's score, so a sound the FLUENT reading
 *  itself says differently from the dictionary is never charged to a
 *  learner who says it the same way (founder: the reading says "nyu"). */
type Word = { w: string; s: number; e: number; ph?: { p: string; a: number }[] }

async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

async function synthesize(text: string, voice: string, language: string, rate = RATE): Promise<Int16Array> {
  const r = await fetch("https://api.cartesia.ai/tts/bytes", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("CARTESIA_API_KEY") ?? ""}`,
      "Cartesia-Version": CARTESIA_VERSION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model_id: CARTESIA_MODEL, transcript: text, voice: { mode: "id", id: voice }, language,
      output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: rate },
    }),
  })
  if (!r.ok) throw new Error(`tts ${r.status} ${(await r.text()).slice(0, 200)}`)
  const buf = new Uint8Array(await r.arrayBuffer())
  return new Int16Array(buf.buffer, buf.byteOffset, Math.floor(buf.byteLength / 2))
}

/** <= 25 s windows cut in the middle of a silence of 0.25 s or more —
 *  scratchpad/tools/align.py's `windows`, the calibration's own cut. */
function windows(pcm: Int16Array): [number, number][] {
  const block = RATE / 100
  const n = Math.floor(pcm.length / block)
  const rms = new Float64Array(n)
  let peak = 0
  for (let b = 0; b < n; b++) {
    let sum = 0
    for (let i = b * block; i < (b + 1) * block; i++) sum += (pcm[i] / 32768) ** 2
    rms[b] = Math.sqrt(sum / block)
    peak = Math.max(peak, rms[b])
  }
  const gate = peak * 0.06
  const cuts: number[] = []
  let start = 0, best: number | null = null, i = 0
  while (i < n) {
    if (rms[i] < gate) {
      let j = i
      while (j < n && rms[j] < gate) j++
      if (j - i >= 25) best = Math.floor((i + j) / 2)
      i = j
    } else {
      i++
    }
    if ((i - start) / 100 > WINDOW_SECONDS && best !== null && best > start) {
      cuts.push(best); start = best; best = null
    }
  }
  const edges = [0, ...cuts, n]
  return edges.slice(0, -1).map((e, k) => [e * block, edges[k + 1] * block])
}

type AzurePhoneme = { Phoneme?: string; AccuracyScore?: number; PronunciationAssessment?: { AccuracyScore?: number } }
type AzureWord = { Word: string; Offset?: number; Duration?: number; ErrorType?: string; Phonemes?: AzurePhoneme[] }

async function timeWords(pcm: Int16Array, text: string, locale: string, withPhonemes = false): Promise<Word[]> {
  const key = Deno.env.get("AZURE_SPEECH_KEY")!, region = Deno.env.get("AZURE_SPEECH_REGION")!
  const cfg = {
    ReferenceText: text, GradingSystem: "HundredMark", Granularity: "Phoneme",
    Dimension: "Comprehensive", EnableMiscue: true, EnableProsodyAssessment: true, PhonemeAlphabet: "IPA",
  }
  const url = `https://${region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1`
    + `?language=${locale}&format=detailed`
  const parts = await Promise.all(windows(pcm).map(async ([s, e]) => {
    const slice = new Uint8Array(pcm.buffer, pcm.byteOffset + s * 2, (e - s) * 2)
    const r = await fetch(url, {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": key,
        "Content-Type": "audio/wav; codecs=audio/pcm; samplerate=16000",
        "Accept": "application/json",
        "Pronunciation-Assessment": btoa(JSON.stringify(cfg)),
      },
      body: wavBytes(new Uint8Array(slice), RATE),
      signal: AbortSignal.timeout(60_000),
    })
    if (!r.ok) throw new Error(`azure ${r.status} ${(await r.text()).slice(0, 200)}`)
    const j = await r.json() as { RecognitionStatus?: string; NBest?: { Words?: AzureWord[] }[] }
    if (j.RecognitionStatus !== "Success") return [] as Word[]
    const base = (s / RATE) * 1000
    return (j.NBest?.[0]?.Words ?? [])
      .filter((w) => w.ErrorType !== "Omission" && (w.Duration ?? 0) > 0)
      .map((w) => ({
        w: w.Word,
        s: Math.round(base + (w.Offset ?? 0) / 10_000),
        e: Math.round(base + ((w.Offset ?? 0) + (w.Duration ?? 0)) / 10_000),
        ...(withPhonemes ? {
          ph: (w.Phonemes ?? []).map((p) => ({
            p: p.Phoneme ?? "",
            a: Math.round(p.AccuracyScore ?? p.PronunciationAssessment?.AccuracyScore ?? 0),
          })),
        } : {}),
      }))
  }))
  return parts.flat()
}

// MARK: The listening audio (2026-11-13)
//
// One fluent reading per challenge that a learner LISTENS to: the challenge
// page opens on it, the script page plays it with the words lighting up. A
// take of its own, in the one voice the challenge was published with
// (`speech_challenges.reference_voice`, null = female), synthesized at 24 kHz
// so it sounds like a voice and not a phone line, timed exactly like the
// scoring references (Azure on a 16 kHz copy), and kept in R2. The scoring
// references above are untouched, so nothing on a board moves.

const LISTEN_VERSION = 1
const LISTEN_RATE = 24_000
const R2_PUBLIC_DEFAULT = "https://pub-83c97a52f2e549718b126bf60f710f1a.r2.dev"

/** 24 kHz → 16 kHz for Azure: a [1 2 1]/4 low-pass, then linear
 *  interpolation at 1.5 input samples per output sample. Timing only — the
 *  learner hears the 24 kHz original. */
function to16k(pcm: Int16Array): Int16Array {
  const n = pcm.length
  const smooth = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const a = pcm[Math.max(0, i - 1)], b = pcm[i], c = pcm[Math.min(n - 1, i + 1)]
    smooth[i] = (a + 2 * b + c) / 4
  }
  const out = new Int16Array(Math.floor(n * 2 / 3))
  for (let i = 0; i < out.length; i++) {
    const p = i * 1.5, k = Math.floor(p), f = p - k
    const v = smooth[k] * (1 - f) + smooth[Math.min(n - 1, k + 1)] * f
    out[i] = Math.max(-32768, Math.min(32767, Math.round(v)))
  }
  return out
}

async function putR2(key: string, bytes: Uint8Array): Promise<string> {
  const account = Deno.env.get("R2_ACCOUNT_ID")!
  const bucket = Deno.env.get("R2_BUCKET") ?? "nawana-shows"
  const { AwsClient } = await import("npm:aws4fetch@1.0.20")
  const aws = new AwsClient({
    accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!,
    secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
    service: "s3", region: "auto",
  })
  const r = await aws.fetch(`https://${account}.r2.cloudflarestorage.com/${bucket}/${key}`, {
    method: "PUT",
    body: bytes,
    headers: { "Content-Type": "audio/wav", "Cache-Control": "public, max-age=31536000, immutable" },
  })
  if (!r.ok) throw new Error(`r2 ${r.status} ${(await r.text()).slice(0, 200)}`)
  const base = (Deno.env.get("R2_PUBLIC_BASE") ?? R2_PUBLIC_DEFAULT).replace(/\/$/, "")
  return `${base}/${key}`
}

// deno-lint-ignore no-explicit-any
async function listen(text: string, language: string, challenge: string | undefined,
                      voices: Record<"male" | "female", string>, admin: any, userId: string,
                      // deno-lint-ignore no-explicit-any
                      supabase: any, req: Request): Promise<Response> {
  const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { "Content-Type": "application/json", ...cors() } })
  let gender: "male" | "female" = "female"
  if (challenge) {
    const { data } = await admin.from("speech_challenges").select("reference_voice").eq("id", challenge).maybeSingle()
    if (data?.reference_voice === "male") gender = "male"
  }
  const voice = voices[gender]
  const key = await sha256(`listen|${LISTEN_VERSION}|${language}|${gender}|${voice}|${CARTESIA_MODEL}|${LISTEN_RATE}|${text}`)
  const { data: hit } = await admin.from("speech_listen_audio").select("url, words").eq("key", key).maybeSingle()
  if (hit && (hit.words as Word[]).some((w) => w.ph)) {
    return json({ version: LISTEN_VERSION, gender, url: hit.url, words: hit.words })
  }
  if (hit) {
    // Made before sounds were kept: re-time the audio already in R2 (no new
    // voice), keeping each sound's score. Free, like a cache hit.
    try {
      const r = await fetch(hit.url)
      if (!r.ok) throw new Error(`r2 get ${r.status}`)
      const buf = new Uint8Array(await r.arrayBuffer())
      const pcm = new Int16Array(buf.buffer.slice(buf.byteOffset + 44, buf.byteOffset + buf.byteLength - ((buf.byteLength - 44) % 2)))
      const words = await timeWords(to16k(pcm), text, "en-US", true)
      if (words.length) {
        await admin.from("speech_listen_audio").update({ words }).eq("key", key)
        return json({ version: LISTEN_VERSION, gender, url: hit.url, words })
      }
    } catch (_) { /* fall through to what was on file */ }
    return json({ version: LISTEN_VERSION, gender, url: hit.url, words: hit.words })
  }

  if (!Deno.env.get("R2_ACCOUNT_ID") || !Deno.env.get("R2_ACCESS_KEY_ID") || !Deno.env.get("R2_SECRET_ACCESS_KEY")) {
    return errorResponse(503, "not_configured")
  }
  const rec = await recordFreeUsage({
    supabase, userId, action: "speech_reference", purpose: SOURCE_FN, dailyCap: DAILY_CAP,
    sourceFn: SOURCE_FN, idempotencyKey: req.headers.get("X-Idempotency-Key") ?? crypto.randomUUID(),
    metadata: { language, chars: text.length, listen: true, gender },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }
  try {
    const pcm = await synthesize(text, voice, language, LISTEN_RATE)
    const words = await timeWords(to16k(pcm), text, "en-US", true)
    const bytes = new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength)
    const url = await putR2(`speech/${language}/${key}.wav`, wavBytes(bytes, LISTEN_RATE))
    await admin.from("speech_listen_audio").upsert({
      key, version: LISTEN_VERSION, language, gender, voice_id: voice, url, words,
    })
    return json({ version: LISTEN_VERSION, gender, url, words })
  } catch (e) {
    return errorResponse(502, "listen audio failed", String(e).slice(0, 300))
  }
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")
  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed
  if (!Deno.env.get("AZURE_SPEECH_KEY") || !Deno.env.get("CARTESIA_API_KEY")) {
    return errorResponse(503, "not_configured")
  }

  let body: { text?: string; language?: string; listen?: boolean; challenge?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const text = (body.text ?? "").trim()
  const language = (body.language ?? "").trim().toLowerCase()
  if (!text || !language) return errorResponse(400, "text and language required")
  if (text.length > MAX_CHARS) return errorResponse(400, "text too long")
  const voices = VOICES[language]
  if (!voices) return errorResponse(400, "unsupported language")

  const admin = serviceRoleClient()

  if (body.listen) return await listen(text, language, body.challenge, voices, admin, user.id, supabase, req)

  const keys = {
    male: await sha256(`${VERSION}|${language}|male|${voices.male}|${CARTESIA_MODEL}|${text}`),
    female: await sha256(`${VERSION}|${language}|female|${voices.female}|${CARTESIA_MODEL}|${text}`),
  }
  const { data: cached } = await admin.from("speech_references")
    .select("key, words").in("key", [keys.male, keys.female])
  const found = new Map((cached ?? []).map((r: { key: string; words: Word[] }) => [r.key, r.words]))
  if (found.has(keys.male) && found.has(keys.female)) {
    return new Response(JSON.stringify({ version: VERSION, male: found.get(keys.male), female: found.get(keys.female) }),
      { headers: { "Content-Type": "application/json", ...cors() } })
  }

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "speech_reference", purpose: SOURCE_FN, dailyCap: DAILY_CAP,
    sourceFn: SOURCE_FN, idempotencyKey: req.headers.get("X-Idempotency-Key") ?? crypto.randomUUID(),
    metadata: { language, chars: text.length },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  try {
    const out: Record<"male" | "female", Word[]> = { male: [], female: [] }
    await Promise.all((["male", "female"] as const).map(async (g) => {
      if (found.has(keys[g])) { out[g] = found.get(keys[g])!; return }
      const pcm = await synthesize(text, voices[g], language)
      out[g] = await timeWords(pcm, text, "en-US")
      await admin.from("speech_references").upsert({
        key: keys[g], version: VERSION, language, gender: g, voice_id: voices[g], words: out[g],
      })
    }))
    return new Response(JSON.stringify({ version: VERSION, ...out }),
      { headers: { "Content-Type": "application/json", ...cors() } })
  } catch (e) {
    return errorResponse(502, "reference failed", String(e).slice(0, 300))
  }
})
