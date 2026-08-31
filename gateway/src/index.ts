// futurevoice-gateway — realtime Talk relay on Cloudflare Workers.
//
// GET /call (WebSocket upgrade) -> a fresh CallSession Durable Object.
// Everything interesting lives in session.ts; this file only routes.

import { CallSession } from "./session"
import type { Env } from "./supabase"

export { CallSession }

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    if (url.pathname === "/health") {
      return new Response("ok", { status: 200 })
    }
    // Debug: is OUTBOUND WebSocket working in this runtime at all? Connects
    // to a public echo server, sends one message, reports what came back.
    // Exists because local workerd killed the Gemini socket with "Network
    // connection lost" right after open (2026-08-31) — this separates "our
    // setup message is wrong" from "outbound WS is broken here".
    if (url.pathname === "/probe-ws") {
      // Dev-only: on a deployed worker this would be an open connect-anywhere
      // relay (SSRF primitive), so it exists only while auth is off too.
      if (env.DEV_ALLOW_ANON !== "1") return new Response("not found", { status: 404 })
      const target = url.searchParams.get("target") ?? "https://echo.websocket.org/"
      try {
        const resp = await fetch(target, { headers: { Upgrade: "websocket" } })
        const ws = resp.webSocket
        if (!ws) return new Response(`no webSocket, status ${resp.status}`, { status: 500 })
        ws.accept()
        const result = await new Promise<string>((resolve) => {
          const timer = setTimeout(() => resolve("TIMEOUT"), 6000)
          ws.addEventListener("message", (ev) => {
            clearTimeout(timer)
            resolve(`MESSAGE: ${String(ev.data).slice(0, 200)}`)
          })
          ws.addEventListener("close", (ev) => {
            clearTimeout(timer)
            resolve(`CLOSED ${ev.code} ${ev.reason}`)
          })
          ws.addEventListener("error", (ev) => {
            clearTimeout(timer)
            resolve(`ERROR ${(ev as ErrorEvent).message ?? ""}`)
          })
          // setup=1: speak the Live protocol instead of a junk line, so a
          // setupComplete here proves message + auth + transport end-to-end.
          if (url.searchParams.get("setup") === "1") {
            ws.send(JSON.stringify({
              setup: {
                model: "models/gemini-3.5-transcribe-live",
                generationConfig: { responseModalities: ["TEXT"] },
              },
            }))
          } else {
            ws.send("hello from gateway")
          }
        })
        try { ws.close() } catch { /* done */ }
        return new Response(result)
      } catch (e) {
        return new Response(`THREW ${String(e)}`, { status: 500 })
      }
    }
    if (url.pathname === "/call") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return new Response("expected websocket", { status: 426 })
      }
      // A unique DO per call: no name to collide on, nothing persisted —
      // the object IS the call, and dies with it.
      const id = env.CALL_SESSION.newUniqueId()
      return env.CALL_SESSION.get(id).fetch(request)
    }
    return new Response("not found", { status: 404 })
  },
} satisfies ExportedHandler<Env>
