// Gemini generateContent proxy.
//
// Body: {
//   model: string                    // e.g. "gemini-2.5-flash"
//   system_instruction?: { parts: [{ text }] }
//   contents: Array<{ role: "user" | "model", parts: [{ text }] }>
//   generationConfig?: object
// }
//
// Forwards exactly as Gemini's `models/{model}:generateContent` expects.
// The iOS app sends the same shape it'd send to Gemini directly — we just
// strip the `?key=` query param and inject the server-side key.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { requireUser, handlePreflight, errorResponse, cors } from "../_shared/auth.ts"

Deno.serve(async (req) => {
  const pre = handlePreflight(req)
  if (pre) return pre
  if (req.method !== "POST") return errorResponse(405, "method not allowed")

  const authed = await requireUser(req)
  if (authed instanceof Response) return authed

  const apiKey = Deno.env.get("GEMINI_API_KEY")
  if (!apiKey) return errorResponse(500, "server missing GEMINI_API_KEY")

  let body: { model?: string; [k: string]: unknown }
  try {
    body = await req.json()
  } catch {
    return errorResponse(400, "invalid json body")
  }
  const model = body.model ?? "gemini-2.5-flash"
  // Strip our own field — Gemini doesn't recognize `model` in the body.
  const { model: _strip, ...geminiBody } = body

  const upstream = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(geminiBody),
    },
  )

  if (!upstream.ok) {
    const detail = await upstream.text()
    return errorResponse(upstream.status, "gemini upstream error", detail.slice(0, 500))
  }

  const text = await upstream.text()
  return new Response(text, {
    status: 200,
    headers: { "Content-Type": "application/json", ...cors() },
  })
})
