// The reply on Claude (2026-10-21) — the same turn `reply.ts` streams from
// Gemini, through the Anthropic Messages API, for models named "claude-…".
//
// Why: Haiku 5.5 is ~1/7 of 3.6-flash per token (1/15 from 2027-01-01, when
// 3.6-flash leaves its introductory price) and measured faster to the first
// word on the live call prompt (median 0.78 s vs 1.11 s, 4 languages × 4).
// Probes on the live prompts, same day: corrections 7/236 false vs 1/236 for
// 3.6-flash (flash-lite: 90/236); beginner turns with two real questions
// 4/112 vs 3/112 once `CLAUDE_ADDENDUM` is appended (9/112 without it).
//
// What differs from the Gemini path, and why each is safe:
// - CACHE. Anthropic caches by marking blocks (`cache_control`), not by
//   creating a cache object, so there is nothing to create, stretch or
//   delete. Two marks: the system prompt, and the last line of the settled
//   prefix (`ReplyEngine.settledPrefix`), so a generation pays full price
//   only for the last exchange — the same split the Gemini cache makes.
// - ROLES. Claude needs the first message to be the user's and no two in a
//   row from one side; the call opens on the fluent self's greeting and a
//   reopened turn can leave two learner lines adjacent, so both are fixed
//   up here and nowhere else.
// - NO THINKING. Haiku 5.5 answers without it by default, which is the
//   gateway's "minimal" in spirit and measured fine on the probes.

export type Line = { role: "user" | "model"; text: string }

/** Appended to the app's system prompt on Claude only. The rules are already
 *  in the prompt; Haiku keeps them far better when they are restated last
 *  (scripts/beginner-probe.py with EXTRA, 2026-10-21). Gemini never sees it. */
export const CLAUDE_ADDENDUM = `

BEFORE YOU WRITE — the two rules most often broken on this call:
- At most ONE question per turn, and it is the last thing you say. Never a second question after the first, not even a short one. If two things interest you, ask one now and keep the other for a later turn.
- If the prompt above has a "HOW TO ASK — THIS LEARNER IS A BEGINNER" section, it outranks everything else, greetings and first turns included: the one question must be short and answerable in a few words — never "tell me about…", "how was your day?", "how are you feeling?", "what kind of…", "why…". Ask a fact instead ("Are you at home?", "Did you work today?").`

export function isClaudeModel(model: string): boolean {
  return model.startsWith("claude-")
}

export interface ClaudeUsage {
  input: number
  cacheRead: number
  cacheWrite: number
  output: number
}

type Block = { type: "text"; text: string; cache_control?: { type: "ephemeral" } }
type Message = { role: "user" | "assistant"; content: Block[] }

/** The history as Claude messages. `cachedThrough` = how many leading lines
 *  are the settled prefix; the message holding its last line is marked. */
export function claudeMessages(history: Line[], cachedThrough: number): Message[] {
  const out: Message[] = []
  let marked = -1
  history.forEach((line, i) => {
    const role = line.role === "model" ? "assistant" : "user"
    const prev = out[out.length - 1]
    if (prev && prev.role === role) prev.content[0].text += `\n${line.text}`
    else out.push({ role, content: [{ type: "text", text: line.text }] })
    if (i === cachedThrough - 1) marked = out.length - 1
  })
  if (out.length === 0 || out[0].role === "assistant") {
    out.unshift({ role: "user", content: [{ type: "text", text: "(call connected)" }] })
    if (marked >= 0) marked += 1
  }
  // A generation always answers the learner; a history ending on our own
  // line would be read as a prefill to continue.
  if (out[out.length - 1].role === "assistant") {
    out.push({ role: "user", content: [{ type: "text", text: "(go on)" }] })
  }
  if (marked >= 0) out[marked].content[0].cache_control = { type: "ephemeral" }
  return out
}

/** One streaming generation. Resolves to the full text; an abort resolves
 *  with what was written so far, like the Gemini stream. */
export async function streamClaude(opts: {
  apiKey: string | undefined
  model: string
  system: string
  messages: Message[]
  signal: AbortSignal
  onDelta: (text: string) => void
  usage: ClaudeUsage
}): Promise<string> {
  if (!opts.apiKey) throw new Error("reply upstream claude: ANTHROPIC_API_KEY not set")
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": opts.apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: 1024,
      stream: true,
      system: [{ type: "text", text: opts.system + CLAUDE_ADDENDUM, cache_control: { type: "ephemeral" } }],
      messages: opts.messages,
    }),
    signal: opts.signal,
  })
  if (!resp.ok || !resp.body) {
    throw new Error(`reply upstream ${opts.model} ${resp.status}: ${(await resp.text()).slice(0, 300)}`)
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
        let event: any
        try { event = JSON.parse(line.slice(5).trim()) } catch { continue }
        if (event?.type === "message_start") {
          const u = event.message?.usage ?? {}
          opts.usage.input += u.input_tokens ?? 0
          opts.usage.cacheRead += u.cache_read_input_tokens ?? 0
          opts.usage.cacheWrite += u.cache_creation_input_tokens ?? 0
        } else if (event?.type === "message_delta") {
          opts.usage.output += event.usage?.output_tokens ?? 0
        } else if (event?.type === "content_block_delta" && event.delta?.type === "text_delta") {
          const text = event.delta.text
          if (typeof text === "string" && text.length > 0) {
            full += text
            opts.onDelta(text)
          }
        } else if (event?.type === "error") {
          throw new Error(`reply upstream ${opts.model} stream error: ${JSON.stringify(event.error).slice(0, 200)}`)
        }
      }
    }
  } catch (e) {
    if (opts.signal.aborted) return full   // barge-in: keep what was voiced
    throw e
  } finally {
    try { reader.releaseLock() } catch { /* released */ }
  }
  return full
}
