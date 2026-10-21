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

/** Appended to the app's system prompt on Claude only; Gemini never sees it.
 *
 *  The first version was a checklist ("BEFORE YOU WRITE — the two rules most
 *  often broken"), and Haiku ran the check IN THE REPLY: "Wait, that's two
 *  questions. Let me redo it." — read aloud on the founder's call, 6/351 in
 *  scripts/reply-leak-probe.py. Telling it that every character is spoken
 *  stopped that (0/378 with thinking off; the residue with thinking on is
 *  what `SpokenGate` catches). The question rules are restated because
 *  Haiku keeps them far better when they come last. */
export const CLAUDE_ADDENDUM = `

HOW YOUR WORDS REACH THEM: everything you write is read aloud, as it is written, to the person on the call, the moment you write it. So write only the words you say to them, once. No notes, no plans, no drafts, no checking your own line, no "wait" followed by a correction, nothing in brackets. Decide what to say before you write; then say it.

ONE QUESTION MARK PER TURN, at most, and it ends the turn. A reaction is a statement, not a question: "Oh, tired." not "Oh, tired?"; "Busy with work, I see." not "Busy with work, huh?". After your question, stop — no second question, not even a guess at their answer ("…? At home?"). If you want to offer a choice, put it inside the one question ("Coffee or tea?").
If the prompt above has a "HOW TO ASK — THIS LEARNER IS A BEGINNER" section, it holds for every turn, the first one too: the question is short and answerable in a few words ("Are you at home?", "Did you work today?"), never "how was your day?" or "tell me about…".
`

/** Thrown when the reply opens with something that must not be spoken —
 *  the hedge then answers the turn on Gemini instead (reply.ts). */
export class SpokenLeakError extends Error {
  constructor(readonly reason: string, readonly sentence: string) {
    super(`reply leak (${reason}): ${sentence.slice(0, 120)}`)
  }
}

/** Is this sentence something no one would SAY to the caller? (2026-10-21.)
 *  Haiku sometimes writes its planning into the reply — "[reaction] 오, …",
 *  "Let's answer: 너가 만드는 건…", "Oops, I slipped in English there" — and
 *  the call reads text aloud as it arrives. Checked one sentence at a time,
 *  before the sentence reaches the voice. Conservative on purpose: English
 *  meta words only where no English speaker would use them in a chat, and
 *  Latin text only in a reply whose language doesn't write it. */
export function spokenLeak(sentence: string, language: string): string | null {
  const lang = language.toLowerCase().split("-")[0]
  if (/[\[\]{}<>]/.test(sentence)) return "bracket"
  // Talking ABOUT the reply instead of giving it. English in every target
  // language, because the model plans in English whatever it speaks.
  if (/\b(the user|the learner|the caller|the reply|my reply|this reply|the prompt|system prompt|the notes|per the notes|my notes say|word count|let's answer|reply must|the rules?:|i broke a rule|let me (redo|rewrite|fix|recheck|check)|(re)?write:|fix(ing)?:|correction:|redo it|one question only|that's two questions|two questions here|i must (not )?(use|reply|answer|write)|i need to check)\b/i.test(sentence)) return "meta"
  if (/≤|\b[AB][12] (words|level)\b/.test(sentence)) return "meta"
  if (lang === "en") return null
  if (lang === "ko" || lang === "ja" || lang === "zh") {
    const latin = sentence.match(/[A-Za-z][A-Za-z'’-]+/g) ?? []
    if (latin.length >= 4) return "latin"
    return null
  }
  // A Latin-script target: an English sentence inside it. Only words that
  // are not also German, Spanish or French ("no", "me", "so", "die" are).
  const english = sentence.match(/\b(the|that|that's|this|it's|wait|should|would|which|question|questions|only|must|need|check|rule|rules|reply|redo|rewrite|fix|fixing|sentence|sentences|words|too|many|let's|i'm|i'll|i've|my|good|fine)\b/gi) ?? []
  if (english.length >= 3) return "english"
  return null
}

/** A question that is a reaction, not a question to answer: a short echo
 *  opening the reply ("Oh, tired?", "그랬구나?") or a tag ("…, huh?"). */
function isEchoQuestion(sentence: string, first: boolean): boolean {
  const s = sentence.trim()
  if (/(\bhuh|\bright|isn't it|aren't you|don't you|\beh|\bno|\boder|\bnicht|\bne|\bhein|\bnon)\s*[?？]$/i.test(s)) return true
  if (!first) return false
  // Korean reacts with a rising "so that's how it is?" ending.
  if (/(구나|군|거야|거지|잖아)\s*[?？]$/.test(s)) return true
  const latin = /[A-Za-zÀ-ÿ]/.test(s)
  return latin ? s.split(/\s+/).length <= 3 : s.replace(/\s/g, "").length <= 8
}

/** Holds the stream back to whole sentences and checks each before it goes
 *  on. The voice is sent sentence by sentence anyway (session.ts
 *  `routeDelta`), so this costs the call no audio latency — only the text on
 *  screen arrives a sentence at a time.
 *
 *  Two things stop a reply here. A sentence that must not be spoken
 *  (`spokenLeak`). And a SECOND question: the prompt asks for one question
 *  that ends the turn, and Haiku asks two two-to-three times as often as
 *  3.6-flash did (probe, 2026-10-21: ~8% of turns vs 2.7%); words could not
 *  close the gap, so the code holds the line — the turn ends where the first
 *  real question did. A choice continuing it ("…? Or …?") is the same
 *  question. */
export class SpokenGate {
  private pending = ""
  private sentences = 0
  private asked = false
  emitted = ""
  constructor(private language: string, private emit: (text: string) => void) {}

  /** Returns false once the reply should stop after what was already said:
   *  the caller stops the stream and keeps `emitted`. Throws when the very
   *  first sentence leaks, so the turn can go to the fallback whole. */
  push(delta: string): boolean {
    this.pending += delta
    // A sentence ends at a terminator followed by space, at a CJK terminator,
    // or at a line break. The tail after the last such point waits.
    const re = /[.!?…](?=\s)|[。！？]|\n/g
    let ok = true
    for (let m; ok && (m = re.exec(this.pending)) !== null;) {
      const end = m.index + m[0].length
      const sentence = this.pending.slice(0, end)
      this.pending = this.pending.slice(end)
      re.lastIndex = 0
      ok = this.release(sentence)
    }
    return ok
  }

  /** The stream ended: the tail is a sentence too. */
  finish(): boolean {
    const tail = this.pending
    this.pending = ""
    return tail.trim().length === 0 ? true : this.release(tail)
  }

  private release(text: string): boolean {
    if (text.trim().length === 0) {
      // Whitespace between sentences: keep it, it is the word boundary.
      this.emitted += text
      this.emit(text)
      return true
    }
    const reason = spokenLeak(text, this.language)
    if (reason) {
      if (this.emitted.trim().length === 0) throw new SpokenLeakError(reason, text)
      console.log(`reply leak cut (${reason}): ${text.slice(0, 160)}`)
      return false
    }
    const trimmed = text.trim()
    const question = /[?？]$/.test(trimmed)
    const choice = /^(or\b|oder\b|아니면|それとも|o\b|ou\b)/i.test(trimmed)
    if (question && this.asked && !choice) return false
    if (question && !isEchoQuestion(trimmed, this.sentences === 0)) this.asked = true
    this.sentences += 1
    this.emitted += text
    this.emit(text)
    return true
  }
}

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
  /** The call's language, for the spoken-leak check. */
  language: string
  /** "" = the API default (adaptive); "adaptive" | "disabled". */
  thinking?: string
  /** "" = the model default (medium on Haiku 5.5); low | medium | high. */
  effort?: string
  signal: AbortSignal
  onDelta: (text: string) => void
  usage: ClaudeUsage
}): Promise<string> {
  if (!opts.apiKey) throw new Error("reply upstream claude: ANTHROPIC_API_KEY not set")
  // Its own abort, so a leak found mid-reply can stop the upstream without
  // the caller's signal (which means a barge-in) being involved. A barge-in
  // also CANCELS the reader: measured 2026-10-21 (test/claude-reply-check.mjs
  // barge-in loop), aborting the fetch alone left a pending `read()` that
  // never settled about half the time, and the reply — and the turn — hung.
  const upstream = new AbortController()
  let reader: ReadableStreamDefaultReader<Uint8Array> | null = null
  const onOuterAbort = () => {
    upstream.abort()
    reader?.cancel().catch(() => { /* already closed */ })
  }
  if (opts.signal.aborted) return ""
  opts.signal.addEventListener("abort", onOuterAbort)
  let resp: Response
  try { resp = await fetch("https://api.anthropic.com/v1/messages", {
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
      ...(opts.thinking ? { thinking: { type: opts.thinking } } : {}),
      ...(opts.effort ? { output_config: { effort: opts.effort } } : {}),
    }),
    signal: upstream.signal,
  }) } catch (e) {
    opts.signal.removeEventListener("abort", onOuterAbort)
    if (opts.signal.aborted) return ""   // barge-in before the first byte
    throw e
  }
  if (!resp.ok || !resp.body) {
    opts.signal.removeEventListener("abort", onOuterAbort)
    throw new Error(`reply upstream ${opts.model} ${resp.status}: ${(await resp.text()).slice(0, 300)}`)
  }

  const gate = new SpokenGate(opts.language, opts.onDelta)
  let cut = false
  reader = resp.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ""
  try {
    for (;;) {
      if (opts.signal.aborted) return gate.emitted
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
          if (typeof text === "string" && text.length > 0 && !gate.push(text)) {
            cut = true
            upstream.abort()
            return gate.emitted
          }
        } else if (event?.type === "error") {
          throw new Error(`reply upstream ${opts.model} stream error: ${JSON.stringify(event.error).slice(0, 200)}`)
        }
      }
    }
    if (!gate.finish()) cut = true
  } catch (e) {
    if (e instanceof SpokenLeakError) { upstream.abort(); throw e }
    if (opts.signal.aborted || cut) return gate.emitted   // barge-in: keep what was voiced
    throw e
  } finally {
    opts.signal.removeEventListener("abort", onOuterAbort)
    try { reader.releaseLock() } catch { /* released */ }
  }
  return gate.emitted
}
