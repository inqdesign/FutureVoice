// A cover picture for a learner's OWN speech script (2026-11-16, founder:
// "when a user makes their own script, we should also create a cover image").
// The challenges' pictures are drawn by hand in Dear RoRo's coloured-pencil
// style (`day-cover-style.json`) with gpt-image-2; this draws the learner's
// script the same way, so My scripts wears the same cards as the challenges.
//
// Two calls: flash-lite turns the script into ONE scene line (the person who
// gives this speech, what they wear and hold), then gpt-image-2 draws it on
// flat cream. The phone keys the cream to alpha and keeps the picture in
// Documents (`ScriptCover`); nothing is kept here — no Storage, no table.
//
// POST { title, summary?, body?, language?, gender? } → 200 { cover } (base64 PNG, 1024²)
// 402 not_entitled (own scripts are a paid feature) · 429 rate_limited · 502 cover_failed
// Recorded as a free, capped action (`speech_cover`, ~$0.05 a picture upstream).
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"
import { recordFreeUsage, rateLimitedResponse, serviceRoleClient } from "../_shared/credits.ts"

const SOURCE_FN = "speech-cover"
const DAILY_CAP = 12
const SCENE_MODEL = "gemini-3.1-flash-lite"
const IMAGE_MODEL = "gpt-image-2"
const CREAM = "#FBF8F0"

/** Dear RoRo's day-cover style, the one the challenge pictures are drawn in. */
const STYLE = {
  medium: "soft coloured-pencil and wax-crayon texture on smooth paper — every shape is a flat fill of colour with a fine grainy pencil texture inside",
  shapes: "big simple flat shapes, slightly naive and hand-drawn; clothes and things are solid colour blocks; a pattern (a check, a stripe) is drawn plainly in the same grainy pencil",
  lines: "very few — a thin dark pencil line only where one shape meets another of the same colour, a fold, a sleeve edge or a shoe sole",
  figures: "real adult and child proportions, a little elongated, walking, holding or doing things naturally; seen from the side or three-quarter",
  faces: "simple: a small dark dot or short line for the eye, a small nose, a short mouth line; plain warm skin with a light pink tone; hair as one soft shape",
  palette: "few, clear colours taken from the scene — e.g. leaf green, cobalt blue, pale sky blue, cream white, warm brown, a dark green-black; never more than five or six",
  background: "none — the people and the things they hold stand on plain off-white paper, nothing behind them, no ground, no shadow",
  detail: "low — only what tells the moment: clothes, a bag, a cup, a microphone, a folder",
  mood: "quiet, warm, everyday — a moment from an illustrated diary",
  avoid: [
    "any background scene, room, landscape or sky", "ground line or cast shadow", "smooth digital vector look",
    "photo-real rendering", "3D", "anime", "cute exaggerated poses or big heads", "any text, title or lettering",
    "signature", "a frame or border",
  ],
}

function sceneSystem(gender: "male" | "female"): string {
  return `You pick the ONE picture for the cover of a speech someone will read out loud.
Draw the speaker: a ${gender === "male" ? "man" : "woman"} in the role this speech is given in
(a host, a pilot, a job candidate, a teacher, a guide, someone at a wedding…), full figure,
what they wear and the one or two things they hold or stand at (a microphone, a podium, cue cards, a folder, a cup).
Rules:
- An ordinary person. Never a real or famous person, even when the speech names one; never their likeness.
- Nothing with words on it: no signs, screens, banners, book titles, logos or brands. No flags.
- No room, no background, no crowd. One person.
- Nothing violent, sexual or medical.
Answer JSON only: {"scene": "<one English sentence, at most 35 words>"}`
}

async function writeScene(title: string, summary: string, body: string, gender: "male" | "female"): Promise<string | null> {
  const key = Deno.env.get("GEMINI_API_KEY")
  if (!key) return null
  const text = `Title: ${title}\nWhat it is: ${summary}\nThe speech (start):\n${body}`
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${SCENE_MODEL}:generateContent?key=${key}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: sceneSystem(gender) }] },
        contents: [{ role: "user", parts: [{ text }] }],
        generationConfig: { maxOutputTokens: 300, responseMimeType: "application/json" },
      }),
    },
  )
  if (!r.ok) { console.error("scene", r.status, (await r.text()).slice(0, 300)); return null }
  try {
    const out = await r.json()
    const raw = (out?.candidates?.[0]?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("")
    const scene = String(JSON.parse(raw)?.scene ?? "").trim()
    return scene.length > 8 ? scene.slice(0, 400) : null
  } catch { return null }
}

function imagePrompt(scene: string): string {
  return "Illustration in this exact style (JSON):\n" + JSON.stringify(STYLE) +
    `\n\nScene: ${scene}. One person, full figure, centred, on a plain light cream background, colour ${CREAM}, ` +
    "one flat even colour from edge to edge: no paper grain, no vignette, no ground, no shadow, nothing behind the figure. " +
    "Leave a generous margin of background around the figure. No text, no lettering, no frame."
}

async function draw(scene: string): Promise<string | null> {
  const key = Deno.env.get("OPENAI_API_KEY")
  if (!key) return null
  const r = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: IMAGE_MODEL, prompt: imagePrompt(scene), size: "1024x1024", quality: "medium", n: 1,
      background: "opaque", output_format: "png",
    }),
  })
  if (!r.ok) { console.error("image", r.status, (await r.text()).slice(0, 300)); return null }
  const out = await r.json().catch(() => null)
  return (out?.data?.[0]?.b64_json as string | undefined) ?? null
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")
  const authed = await requireUser(req)
  if (authed instanceof Response) return authed
  const { user, supabase } = authed
  if (!Deno.env.get("OPENAI_API_KEY") || !Deno.env.get("GEMINI_API_KEY")) return errorResponse(503, "not_configured")

  let body: { title?: string; summary?: string; body?: string; language?: string; gender?: string }
  try { body = await req.json() } catch { return errorResponse(400, "invalid json body") }
  const title = String(body.title ?? "").trim().slice(0, 200)
  const summary = String(body.summary ?? "").trim().slice(0, 600)
  const text = String(body.body ?? "").trim().slice(0, 1500)
  if (!title && !text) return errorResponse(400, "title or body required")
  // Most learners are women; a speaker we know nothing about is drawn as one
  // (the same rule the challenge pictures follow).
  const gender = body.gender === "male" ? "male" : "female"

  // Own scripts are a paid feature; the picture is part of it.
  const admin = serviceRoleClient()
  const { data: entitled, error: entErr } = await admin.rpc("voice_owner_is_entitled", { p_user_id: user.id })
  if (entErr) return errorResponse(500, "entitlement check failed", entErr.message)
  if (!entitled) return errorResponse(402, "not_entitled")

  const rec = await recordFreeUsage({
    supabase, userId: user.id, action: "speech_cover", purpose: SOURCE_FN, dailyCap: DAILY_CAP,
    sourceFn: SOURCE_FN, idempotencyKey: req.headers.get("X-Idempotency-Key") ?? crypto.randomUUID(),
    metadata: { language: body.language ?? null, model: IMAGE_MODEL },
  })
  if (!rec.ok) {
    if (rec.reason === "rate_limited") return rateLimitedResponse(cors())
    return errorResponse(500, "usage record failed", rec.detail)
  }

  try {
    const scene = await writeScene(title, summary, text, gender) ??
      `a ${gender === "male" ? "man" : "woman"} in smart everyday clothes standing at a small wooden podium, holding a few cue cards`
    const cover = await draw(scene)
    if (!cover) return errorResponse(502, "cover_failed")
    return new Response(JSON.stringify({ cover, scene }), { headers: { "Content-Type": "application/json", ...cors() } })
  } catch (e) {
    console.error("speech-cover failed", String(e))
    return errorResponse(502, "cover_failed")
  }
})
