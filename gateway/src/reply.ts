// Reply engine — the conversation brain of the gateway cascade.
//
// One streaming generateContent call per turn, direct to Gemini with the
// server-held key on a warm HTTPS connection: no per-turn auth, no charge
// RPC, no edge hop — the pre-work that made the old pipeline's gemini_first
// slow is structurally gone here. Text deltas stream out via callback and
// the whole call is abortable, which is what barge-in needs.
//
// Plain prose out, NOT the {reply, suggestion} JSON of the HTTP pipeline:
// the suggestion is display-deferred in the app anyway and moves to its own
// async call in Phase 2 — the voice must never wait on coaching.

const API_HOST = "https://generativelanguage.googleapis.com"

export interface ReplyConfig {
  apiKey: string
  /** e.g. "gemini-3.6-flash" — mirror GeminiClient.Model's default. */
  model: string
  system: string
}

export class ReplyEngine {
  constructor(private config: ReplyConfig) {}

  /** Stream one reply for the given history. Resolves to the full text.
   *  Aborting mid-stream resolves with what was written so far. */
  async generate(
    history: { role: "user" | "model"; text: string }[],
    signal: AbortSignal,
    onDelta: (text: string) => void,
  ): Promise<string> {
    const body = {
      systemInstruction: { parts: [{ text: this.config.system }] },
      contents: history.map((t) => ({ role: t.role, parts: [{ text: t.text }] })),
      generationConfig: {
        maxOutputTokens: 1024,   // thinking tokens bill against this too
        // "minimal" halves TTFT vs "low" (~1.5 s vs ~2.9 s, measured
        // 2026-08-31 in test/probe-reply-ttft.mjs) and a spoken reply is
        // still MORE deliberation than the 2.5-era pipeline ran with
        // (thinkingBudget 0). Latency is the product here.
        thinkingConfig: { thinkingLevel: "minimal" },
      },
    }
    const resp = await fetch(
      `${API_HOST}/v1beta/models/${this.config.model}:streamGenerateContent?alt=sse&key=${this.config.apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal,
      },
    )
    if (!resp.ok || !resp.body) {
      throw new Error(`reply upstream ${resp.status}: ${(await resp.text()).slice(0, 300)}`)
    }

    let full = ""
    const reader = resp.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""
    try {
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split("\n")
        buffer = lines.pop() ?? ""
        for (const line of lines) {
          if (!line.startsWith("data:")) continue
          const payload = line.slice(5).trim()
          if (!payload || payload === "[DONE]") continue
          let chunk: any
          try { chunk = JSON.parse(payload) } catch { continue }
          const parts = chunk?.candidates?.[0]?.content?.parts
          if (!Array.isArray(parts)) continue
          for (const part of parts) {
            if (typeof part?.text === "string" && part.text.length > 0) {
              full += part.text
              onDelta(part.text)
            }
          }
        }
      }
    } catch (e) {
      if (signal.aborted) return full   // barge-in: keep what was voiced
      throw e
    } finally {
      try { reader.releaseLock() } catch { /* released */ }
    }
    return full
  }
}
