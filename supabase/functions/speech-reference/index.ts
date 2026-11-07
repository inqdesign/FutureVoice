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

type Word = { w: string; s: number; e: number }

async function sha256(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("")
}

async function synthesize(text: string, voice: string, language: string): Promise<Int16Array> {
  const r = await fetch("https://api.cartesia.ai/tts/bytes", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("CARTESIA_API_KEY") ?? ""}`,
      "Cartesia-Version": CARTESIA_VERSION,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model_id: CARTESIA_MODEL, transcript: text, voice: { mode: "id", id: voice }, language,
      output_format: { container: "raw", encoding: "pcm_s16le", sample_rate: RATE },
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

type AzureWord = { Word: string; Offset?: number; Duration?: number; ErrorType?: string }

async function timeWords(pcm: Int16Array, text: string, locale: string): Promise<Word[]> {
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
      }))
  }))
  return parts.flat()
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

  let body: { text?: string; language?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const text = (body.text ?? "").trim()
  const language = (body.language ?? "").trim().toLowerCase()
  if (!text || !language) return errorResponse(400, "text and language required")
  if (text.length > MAX_CHARS) return errorResponse(400, "text too long")
  const voices = VOICES[language]
  if (!voices) return errorResponse(400, "unsupported language")

  const admin = serviceRoleClient()
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
