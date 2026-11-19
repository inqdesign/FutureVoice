// Phoneme-level pronunciation assessment of ONE recorded take — Azure Speech
// (Pronunciation Assessment, scripted mode). Free to the learner, daily-capped.
//
// Body: {
//   audio_b64: string,   // WAV, 16 kHz mono PCM16, ≤ 30 s (the REST short-audio limit)
//   language:  string,   // target language code ("en", "de", "ja", "ko", "es", "fr", "zh")
//   reference: string,   // the line the learner was reading — scripted assessment
//   accent?:   string,   // the learner's voice accent id ("en-GB", "es-ES") → locale
//   surface?:  string    // "shadow" | "speech" | …, ledger metadata only
// }
// Returns (200): {
//   score, accuracy, fluency, completeness, prosody?,   // 0–100, full-text level
//   recognized,                                          // Azure's own read of the audio
//   words: [{ word, accuracy, error, offset_ms, duration_ms,
//             phonemes: [{ phoneme, accuracy }] }]
// }
// 204 when Azure heard no speech. 503 `not_configured` when the secrets are
// unset — the app treats every non-200 as "no assessment", never as a failed
// take.
//
// Why this exists (2026-11-03): every speaking score in the app was a
// TRANSCRIPT compared with the target. A transcriber writes the word the
// learner was reaching for whenever it can tell what that was, so an accent
// that is still intelligible scored 100 — the number measured whether a
// machine could understand them, not how they pronounced it. This is the one
// reader in the app that hears the SOUNDS: per-phoneme accuracy against a
// native model, for every target language the app ships (prosody — stress and
// intonation — is en-US only on Azure's side).
//
// Why Azure and not the model that already transcribes the take: a pronunciation
// verdict from an LLM listening to audio was measured at chance on accent
// (Korean cross-lingual probe, 2026-09), and a score must be computed, never
// written ("Deterministic scores stay deterministic"). Azure's number is a
// model's too, but it is a per-phoneme acoustic score with a fixed rubric, and
// the same take gets the same number twice.
//
// Cost: billed by audio second at the standard STT rate (~$1 per audio HOUR),
// so a 6-second shadow take is ~$0.002. The cap below is abuse insurance, not
// a budget.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse } from "../_shared/credits.ts"

const SOURCE_FN = "pronunciation"
// Shadow takes are one line each; a speech take is cut into ~12 s pieces, so a
// three-minute speech is ~15 calls. 1,200 a day is a learner who did nothing
// else all day; past it the take is still scored by words, just not by sound.
const DAILY_CAP = 1200
// 30 s of 16 kHz mono PCM16 is 960 KB; base64 ×4/3. The REST short-audio
// endpoint assesses up to ~30 s; a longer file is the caller's to cut.
const MAX_AUDIO_BYTES = 1_100_000
const MAX_REFERENCE_CHARS = 1_500

/// The Azure locale a take is judged against: ONE per language, with one
/// exception (Castilian). English is ALWAYS en-US (2026-11-03, founder's own
/// take): the learner's voice ACCENT used to pick the model, and en-GB /
/// en-AU return no phoneme names and copy the word score onto every
/// phoneme — a "some 40" with nothing underneath to say which sound. en-US
/// is the only locale that scores the SOUNDS (IPA per phoneme) and the
/// prosody, and the voice accent is how the fluent self sounds, not the
/// yardstick the learner is measured by. A learner aiming at British
/// English is still judged by the American model — the word score is
/// lenient about vowels, and a per-sound read beats a per-word one.
const LOCALE_BY_ACCENT: Record<string, string> = {
  "es-MX": "es-MX", "es-ES": "es-ES",
  "fr-FR": "fr-FR", "fr-CA": "fr-CA",
}
const LOCALE_BY_LANGUAGE: Record<string, string> = {
  en: "en-US", de: "de-DE", ja: "ja-JP", ko: "ko-KR", es: "es-MX", fr: "fr-FR", zh: "zh-CN",
}
// zh-CN scores each SYLLABLE with its tone ("mai 3") — but only in its own
// alphabet: asked for IPA it returns no phonemes at all (measured
// 2026-11-13). Every other locale keeps IPA.
const NATIVE_ALPHABET_LOCALES = new Set(["zh-CN"])
// Locales whose Azure model can't be trusted to judge a native speaker.
const UNJUDGED_LOCALES = new Set(["ko-KR"])
// Prosody (stress, intonation, rhythm) is assessed by Azure for en-US only.
const PROSODY_LOCALES = new Set(["en-US"])

// The REST short-audio endpoint puts the scores FLAT on NBest / word /
// phoneme (measured 2026-11-03: `NBest[0].AccuracyScore`, `Words[i].ErrorType`,
// `Phonemes[j].AccuracyScore`). The SDK's JSON nests them under
// `PronunciationAssessment`, which is what the docs' samples show — a parser
// written from the docs read every REST answer as "no assessment". Both are
// read, flat first.
type Scores = {
  AccuracyScore?: number; FluencyScore?: number; CompletenessScore?: number
  ProsodyScore?: number; PronScore?: number; ErrorType?: string
}
type AzureWord = Scores & {
  Word: string
  Offset?: number
  Duration?: number
  PronunciationAssessment?: Scores
  Phonemes?: (Scores & {
    Phoneme: string
    PronunciationAssessment?: Scores & { NBestPhonemes?: NBestPhoneme[] }
    NBestPhonemes?: NBestPhoneme[]
  })[]
  Feedback?: { Prosody?: { Intonation?: { ErrorTypes?: string[] } } }
}
type NBestPhoneme = { Phoneme: string; Score: number }
type AzureNBest = Scores & {
  Display?: string
  PronunciationAssessment?: Scores
  Words?: AzureWord[]
}
/** Flat field first (REST), nested second (SDK shape). */
function pick(o: Scores & { PronunciationAssessment?: Scores }, key: keyof Scores) {
  return o[key] ?? o.PronunciationAssessment?.[key]
}
type AzureResponse = { RecognitionStatus?: string; NBest?: AzureNBest[] }

export function localeFor(language: string, accent?: string | null): string | null {
  if (accent && LOCALE_BY_ACCENT[accent]) {
    // An accent of another language than the one being read is a stale pick,
    // not a locale: "en-GB" on a German line must not judge German as English.
    if (LOCALE_BY_ACCENT[accent].slice(0, 2) === language) return LOCALE_BY_ACCENT[accent]
  }
  return LOCALE_BY_LANGUAGE[language] ?? null
}

/** Azure's 100-ns ticks → whole milliseconds. */
const ms = (ticks?: number) => Math.round((ticks ?? 0) / 10_000)
const score = (n?: number) => (typeof n === "number" ? Math.max(0, Math.min(100, Math.round(n))) : null)

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed

  const key = Deno.env.get("AZURE_SPEECH_KEY")
  const region = Deno.env.get("AZURE_SPEECH_REGION")
  if (!key || !region) return errorResponse(503, "not_configured")

  let body: {
    audio_b64?: string; language?: string; reference?: string
    accent?: string | null; surface?: string
  }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }

  const language = (body.language ?? "").trim().toLowerCase()
  const reference = (body.reference ?? "").trim()
  const audioB64 = body.audio_b64 ?? ""
  if (!language || !reference || !audioB64) {
    return errorResponse(400, "audio_b64, language and reference required")
  }
  if (reference.length > MAX_REFERENCE_CHARS) return errorResponse(400, "reference too long")
  const locale = localeFor(language, body.accent)
  if (!locale) return errorResponse(400, "unsupported language")
  // Korean is not judged (2026-11-19). Azure's ko-KR model faults NATIVE
  // speech: five native voices reading "예쁜 카페에서 …" all scored "예쁜"
  // 34–58 and flagged it mispronounced, and the founder, a native speaker,
  // got 37 and was drilled on it over and over. 503 is what the app reads as
  // "no reader", so the pronunciation call judges the words at once and
  // shadowing and speech score as they did before any assessment.
  if (UNJUDGED_LOCALES.has(locale)) return errorResponse(503, "not_configured")
  // The pronunciation call is judged in English only (2026-11-19, founder).
  // Its pass bars were set on en-US and never checked elsewhere: a native
  // voice reading the right sentence passed 0/5 in Japanese, 4/10 in French,
  // 3/5 in Spanish, and two real German learners got 0 passes in 8 takes.
  // Other surfaces (shadowing, speech) keep their scores: nothing there
  // stops a learner on one.
  if (body.surface === "pron_call" && locale !== "en-US") {
    return errorResponse(503, "not_configured")
  }

  let audio: Uint8Array
  try {
    audio = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0))
  } catch {
    return errorResponse(400, "audio_b64 is not base64")
  }
  if (audio.byteLength < 1_000) return errorResponse(400, "audio too short")
  if (audio.byteLength > MAX_AUDIO_BYTES) return errorResponse(413, "audio too long")
  // 16 kHz mono PCM16 WAV: 44-byte header, 32,000 bytes a second.
  const audioMs = Math.round(((audio.byteLength - 44) / 32_000) * 1000)

  // The usage record runs BESIDE the Azure call, not in front of it
  // (2026-11-12): a pronunciation call's learner waits on this answer, and
  // the record was a database round trip before Azure even started. The cap
  // is abuse insurance at a fraction of a cent a read, so a capped request
  // that already reached Azure costs nothing worth the wait.
  const idemKey = req.headers.get("X-Idempotency-Key") ?? crypto.randomUUID()
  const recording = recordFreeUsage({
    supabase, userId: user.id, action: "pronunciation", purpose: "pronunciation",
    dailyCap: DAILY_CAP, sourceFn: SOURCE_FN, idempotencyKey: idemKey,
    metadata: { locale, audio_ms: audioMs, surface: body.surface ?? null },
  })

  const assessment = {
    ReferenceText: reference,
    GradingSystem: "HundredMark",
    Granularity: "Phoneme",
    Dimension: "Comprehensive",
    // Omission / Insertion tags against the reference — the diff the app
    // already draws comes from its own transcript; these are kept so the
    // phoneme list lines up with the reference words.
    EnableMiscue: true,
    EnableProsodyAssessment: PROSODY_LOCALES.has(locale),
    // IPA, so a phoneme the app shows reads the same in German and Korean
    // (the default alphabet is SAPI for English only) — except zh-CN, above.
    ...(NATIVE_ALPHABET_LOCALES.has(locale) ? {} : { PhonemeAlphabet: "IPA" }),
    // What each sound was heard AS (2026-11-04, founder: "show how it
    // sounded"). Measured that day: "프라이트" scored f 38 with p at 100 on
    // this list, and "드링크" scored d 60 with a vowel at 77 — the list is
    // how the app can say "your f came out as p" or "a vowel slipped in".
    // Phoneme names come back for en-US only; elsewhere this is empty.
    NBestPhonemeCount: 3,
  }
  const url = `https://${region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1`
    + `?language=${encodeURIComponent(locale)}&format=detailed`

  let upstream: Response
  try {
    upstream = await fetch(url, {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": key,
        "Content-Type": "audio/wav; codecs=audio/pcm; samplerate=16000",
        "Accept": "application/json",
        // UTF-8 first: `btoa` throws on anything outside Latin-1, so every
        // Korean, Japanese and Chinese reference failed here as a 502
        // before Azure was ever asked (2026-11-19).
        "Pronunciation-Assessment": btoa(String.fromCharCode(
          ...new TextEncoder().encode(JSON.stringify(assessment)))),
      },
      body: audio,
      signal: AbortSignal.timeout(20_000),
    })
  } catch (e) {
    await recording
    return errorResponse(502, "azure unreachable", String(e))
  }
  const rec = await recording
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }
  if (!upstream.ok) {
    const detail = await upstream.text().catch(() => "")
    return errorResponse(502, "azure error", `${upstream.status} ${detail.slice(0, 300)}`)
  }
  const parsed = (await upstream.json().catch(() => null)) as AzureResponse | null
  const best = parsed?.NBest?.[0]
  if (!parsed || parsed.RecognitionStatus !== "Success" || !best
      || typeof pick(best, "AccuracyScore") !== "number") {
    // NoMatch / InitialSilenceTimeout: nothing was said. Not an error.
    return new Response(null, { status: 204, headers: cors() })
  }

  const words = (best.Words ?? []).map((w) => {
    const error = (pick(w, "ErrorType") as string | undefined) ?? "None"
    // Monotone lives under the prosody feedback, not ErrorType (en-US only).
    const monotone = w.Feedback?.Prosody?.Intonation?.ErrorTypes?.includes("Monotone")
    return {
      word: w.Word,
      accuracy: score(pick(w, "AccuracyScore") as number | undefined),
      error: error === "None" && monotone ? "Monotone" : error,
      offset_ms: ms(w.Offset),
      duration_ms: ms(w.Duration),
      phonemes: (w.Phonemes ?? []).map((p) => {
        const nbest = p.NBestPhonemes ?? p.PronunciationAssessment?.NBestPhonemes ?? []
        return {
          phoneme: p.Phoneme,
          accuracy: score(pick(p, "AccuracyScore") as number | undefined),
          // Only when there is something to say: an older app ignores it.
          ...(nbest.length ? { heard: nbest.slice(0, 3).map((c) => ({ phoneme: c.Phoneme, score: Math.round(c.Score) })) } : {}),
        }
      }),
    }
  })

  return new Response(JSON.stringify({
    locale,
    score: score(pick(best, "PronScore") as number | undefined),
    accuracy: score(pick(best, "AccuracyScore") as number | undefined),
    fluency: score(pick(best, "FluencyScore") as number | undefined),
    completeness: score(pick(best, "CompletenessScore") as number | undefined),
    prosody: score(pick(best, "ProsodyScore") as number | undefined),
    recognized: best.Display ?? "",
    words,
  }), { status: 200, headers: { ...cors(), "Content-Type": "application/json" } })
})
