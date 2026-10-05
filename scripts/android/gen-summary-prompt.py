#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lift ConversationEngine.summarySystemPrompt out of the iOS Swift source
into the Android-only `session-summary` edge function.

The summary prompt decides what a talk teaches: the review material, the
scorecard, and — since build 54 — what the fluent self REMEMBERS about the
person (`about_user` objects with a three-way share lock, `kind`, and
`replaces` pointing into the numbered notebook). The first copy of it in
`session-summary/index.ts` was an extract frozen at an older iOS build, and it
drifted: every Android memory line came back as a bare string. So the text is
read out of the Swift source at a pinned iOS REF (default `18661cf`, iOS 1.1.1
— the Android port's baseline), never from the working tree, and never
retyped.

    python3 scripts/android/gen-summary-prompt.py [ios-ref] [--fingerprints]

Writes `supabase/functions/session-summary/prompt.ts`. What is GENERATED
(read from Swift at the ref):
  - the whole `summarySystemPrompt` literal,
  - `CoachingLanguage.contract`'s literal,
  - `registerGuard`'s text (common + ko + ja parts),
  - `unspacedExpressionNote`'s text.
What is HAND-PORTED (small, pinned: the generator fails if the Swift it
stands for changes):
  - the three list interpolations (on-file facts, the numbered remembered
    notes with their age, the share corrections) — each Swift expression is
    matched byte-for-byte (whitespace-normalized) before its TS twin is used,
  - `age(of:at:)`, `LanguageCatalog.englishName`, `.writesSpaces`, `.base`,
    each pinned by a fingerprint of its Swift body.

Fails loudly on any interpolation it has not been taught.
"""
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "supabase/functions/session-summary/prompt.ts"
_ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
REF = _ARGS[0] if _ARGS else "18661cf"


def show(path: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), "show", f"{REF}:{path}"],
                          check=True, capture_output=True, text=True).stdout


ENGINE = show("FutureVoice/Services/ConversationEngine.swift")
COACHING = show("FutureVoice/Services/CoachingLanguage.swift")
CATALOG = show("FutureVoice/Services/LanguageCatalog.swift")


def func_body(src: str, name: str) -> str:
    """The body of `static func <name>(...)` — braces balanced, skipping strings."""
    i = src.index(f"static func {name}(")
    j = src.index("{", i)
    depth, k, in_str = 0, j, False
    while True:
        c = src[k]
        if in_str:
            if c == "\\":
                k += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return src[j + 1:k]
        k += 1


def multiline_literal(body: str, anchor: str) -> str:
    """The `return \"\"\" … \"\"\"` literal after `anchor`, dedented the way Swift
    does it (by the closing delimiter's indent). The closing delimiter's
    indent may not contain a newline, so a literal ending in a blank line
    keeps its trailing `\\n` — exactly as Swift would."""
    m = re.search(re.escape(anchor) + r'"""\n(.*?)\n([ \t]*)"""', body, re.S)
    if not m:
        sys.exit(f"literal after {anchor!r} not found")
    cut = len(m.group(2))
    lines = m.group(1).split("\n")
    out = []
    for l in lines:
        if l.strip() and not l.startswith(" " * cut):
            sys.exit(f"line under-indented for its closing delimiter: {l!r}")
        out.append(l[cut:] if l.strip() else "")
    text = "\n".join(out)
    # A trailing backslash joins the next line in a Swift multi-line literal.
    return re.sub(r"\\\n", "", text)


def split_interpolations(text: str):
    """Yield ('text', s) and ('interp', expr) pieces. `\\(` opens an
    interpolation that runs to its balanced `)`, skipping string literals
    (which may themselves carry nested interpolations)."""
    i, buf = 0, []
    while i < len(text):
        if text.startswith("\\(", i):
            if buf:
                yield ("text", "".join(buf))
                buf = []
            j, depth, in_str = i + 2, 1, False
            while depth:
                c = text[j]
                if in_str:
                    if text.startswith("\\(", j):
                        # nested interpolation inside a string: balance it too
                        d2, j = 1, j + 2
                        while d2:
                            d2 += {"(": 1, ")": -1}.get(text[j], 0)
                            j += 1
                        continue
                    if c == "\\":
                        j += 2
                        continue
                    if c == '"':
                        in_str = False
                elif c == '"':
                    in_str = True
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                j += 1
            yield ("interp", text[i + 2:j - 1])
            i = j
        elif text[i] == "\\":
            # Any other escape in a multi-line literal.
            nxt = text[i + 1]
            buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(nxt) or
                       sys.exit(f"unhandled escape \\{nxt}"))
            i += 2
        else:
            buf.append(text[i])
            i += 1
    if buf:
        yield ("text", "".join(buf))


def unescape(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and not s.startswith("\\(", i):
            nxt = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt) or
                       sys.exit(f"unhandled escape \\{nxt}"))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def literals(chunk: str) -> str:
    """Concatenated single-line Swift string literals in `chunk`, unescaped
    (interpolations left as `\\(...)`)."""
    return "".join(unescape(p) for p in re.findall(r'"((?:[^"\\]|\\.)*)"', chunk))


def norm(expr: str) -> str:
    return re.sub(r"\s+", " ", expr).strip()


def fingerprint(src: str, name: str) -> str:
    return hashlib.sha256(norm(func_body(src, name)).encode()).hexdigest()[:12]


def ts_template(s: str) -> str:
    """Body text for a TS template literal."""
    return s.replace("\\", "\\\\").replace("`", "\\`").replace("${", "\\${")


# ── The hand-ported pieces, pinned ─────────────────────────────────────────
# If any of these Swift bodies change at a newer ref, the TS twin below is
# stale: re-port it, then update the fingerprint.
PINNED = {
    (ENGINE, "age"): "9fa7dc53394b",
    (CATALOG, "englishName"): "d10d7ab844b5",
    (CATALOG, "writesSpaces"): "337b88e9cabd",
    (CATALOG, "base"): "3e2d40bfa431",
}
if "--fingerprints" in sys.argv:
    for (src, name) in PINNED:
        print(name, fingerprint(src, name))
    sys.exit(0)
for (src, name), want in PINNED.items():
    got = fingerprint(src, name)
    if got != want:
        sys.exit(f"{name} changed in Swift ({got} != {want}) — re-port its TS twin in "
                 f"this generator, then update PINNED")

# Swift interpolation (whitespace-normalized) → TS expression. The three list
# expressions are ported by hand; the rest are plain parameters.
INTERP = {
    "languageName": "${languageName}",
    "nativeName": "${nativeName}",
    "contract": "${contract}",
    "profileJSON": "${profileJSON}",
    "expressionBudget": "${expressionBudget}",
    "registerGuard(targetLanguage)": "${registerGuard(opts.targetLanguage)}",
    "unspacedExpressionNote(targetLanguage)": "${unspacedExpressionNote(opts.targetLanguage)}",
    "PromptClock.dayLine(talkDate ?? now)": "${dayLine(opts.talkDate ?? now, utcOffset)}",
    # Built by the client (it holds the person's registers; Android
    # `relationshipRegisterLine`) and inserted as is — "" for everyone else.
    "relationshipRegisterLine(targetLanguage, counterpart: counterpart)": "${opts.relationshipRegisterLine ?? \"\"}",
    # Korean only (iOS `bee9052d`): a polite setting with no level set — a
    # scene character, a stranger, a public figure, a colleague. Also built
    # by the client (Android `ConversationCharacter.politeSettingLine`).
    "politeSettingLine(targetLanguage, counterpart: counterpart, inScene: inScene)": "${opts.politeSettingLine ?? \"\"}",
    norm('knownAboutUser.isEmpty ? "(nothing yet)" : knownAboutUser.map { "- \\($0)" }'
         '.joined(separator: "\\n")'): "${knownBlock}",
    norm('rememberedNotes.isEmpty ? "(nothing yet)" : rememberedNotes.enumerated().map { '
         '"\\($0.offset + 1). (\\(age(of: $0.element.learnedAt, at: now)), '
         '\\($0.element.kind.rawValue)) \\($0.element.text)" }.joined(separator: "\\n")'):
        "${rememberedBlock}",
    norm('shareCorrections.isEmpty ? "(no corrections yet)" : shareCorrections.map { '
         '"- \\($0.from.rawValue) → \\($0.to.rawValue): \\($0.text)" }.joined(separator: "\\n")'):
        "${correctionsBlock}",
}


def render(text: str, table: dict) -> str:
    out = []
    for kind, s in split_interpolations(text):
        if kind == "text":
            out.append(ts_template(s))
        else:
            key = norm(s)
            if key not in table:
                sys.exit(f"unmapped Swift interpolation: \\({key})")
            out.append(table[key])
    return "".join(out)


# ── Extract ────────────────────────────────────────────────────────────────
summary = render(multiline_literal(func_body(ENGINE, "summarySystemPrompt"), "return "), INTERP)

contract = render(multiline_literal(func_body(COACHING, "contract"), "return "),
                  {"targetName": "${targetName}", "nativeName": "${nativeName}"})

# The contract's guard must still be "same English name → empty".
if 'guard targetName != nativeName else { return "" }' not in func_body(COACHING, "contract"):
    sys.exit("CoachingLanguage.contract's guard changed")

reg = func_body(ENGINE, "registerGuard")
if 'guard base == "ko" || base == "ja" else { return "" }' not in reg:
    sys.exit("registerGuard's gate changed")
reg_body = re.sub(r"guard .*?else \{ return \"\" \}", "", reg, count=1)
reg_extra = {lang: literals(block)
             for lang, block in re.findall(r'if base == "(\w+)" \{(.*?)\n        \}', reg_body, re.S)}
reg_common = literals(re.sub(r'if base == "\w+" \{.*?\n        \}', "", reg_body, flags=re.S))
if not reg_common or set(reg_extra) != {"ko", "ja"}:
    sys.exit("registerGuard's shape changed — common + ko + ja expected")

une = func_body(ENGINE, "unspacedExpressionNote")
if 'guard !LanguageCatalog.writesSpaces(targetLanguage) else { return "" }' not in une:
    sys.exit("unspacedExpressionNote's gate changed")
une_text = literals(re.sub(r"guard .*?else \{ return \"\" \}", "", une, count=1))
une_parts = une_text.split("\\(LanguageCatalog.englishName(targetLanguage))")
if len(une_parts) != 2 or "\\(" in "".join(une_parts):
    sys.exit("unspacedExpressionNote's interpolation changed")

for name, s in [("summary", summary), ("contract", contract)]:
    if "\\(" in s:
        sys.exit(f"{name}: a Swift interpolation survived")

J = lambda s: json.dumps(s, ensure_ascii=False)

OUT.write_text(f'''// GENERATED by `scripts/android/gen-summary-prompt.py` from the iOS source at
// `{REF}` (ConversationEngine.summarySystemPrompt, CoachingLanguage.contract,
// registerGuard, unspacedExpressionNote). Do not edit by hand — re-run the
// generator, or the two platforms start remembering the same learner by
// different rules.
//
// HAND-PORTED (pinned by the generator, which fails if the Swift changes):
// the three list blocks below, `age`, `englishName`, `writesSpaces`, `base`.

/** `LanguageCatalog.base` — "zh-Hant" → "zh". */
export function base(code: string): string {{
  return code.split("-")[0] || code
}}

const ENGLISH_NAMES: Record<string, string> = {{
  en: "English", es: "Spanish", de: "German", fr: "French", it: "Italian",
  pt: "Portuguese", ja: "Japanese", ko: "Korean", zh: "Chinese", vi: "Vietnamese",
  th: "Thai", id: "Indonesian", hi: "Hindi", ar: "Arabic", tr: "Turkish",
  ru: "Russian", pl: "Polish", nl: "Dutch",
}}

/**
 * `LanguageCatalog.englishName` — Foundation's English name for the
 * language code, with the Chinese script kept ("Traditional Chinese"): a
 * prompt told plain "Chinese" writes Simplified. Region is dropped, as
 * `localizedString(forLanguageCode:)` drops it.
 */
export function englishName(code: string): string {{
  const b = base(code)
  if (b === "zh" && /-Hant\\b/i.test(code)) return "Traditional Chinese"
  if (b === "zh" && /-Hans\\b/i.test(code)) return "Simplified Chinese"
  if (ENGLISH_NAMES[b]) return ENGLISH_NAMES[b]
  try {{
    const n = new Intl.DisplayNames(["en"], {{ type: "language" }}).of(b)
    if (n && n !== b) return n.replace(/\\b\\p{{L}}/gu, (c) => c.toUpperCase())
  }} catch {{ /* no ICU data: fall through */ }}
  return code.toUpperCase()
}}

/** `LanguageCatalog.writesSpaces` — Japanese and Chinese don't. */
export function writesSpaces(code: string): boolean {{
  return !["ja", "zh"].includes(base(code))
}}

/** Whole calendar days in the learner's zone (`PromptClock.calendarDays`):
 *  a line heard at 23:00 is "yesterday" at 08:00. The server has no zone of
 *  its own, so the client sends its UTC offset in minutes. */
export function calendarDays(from: Date, to: Date, utcOffsetMinutes = 0): number {{
  const day = (d: Date) => Math.floor((d.getTime() + utcOffsetMinutes * 60_000) / 86_400_000)
  return Math.max(0, day(to) - day(from))
}}

/** `ConversationEngine.age(of:at:)` — calendar days (iOS 1.1.4). */
export function age(learnedAt: Date, now: Date = new Date(), utcOffsetMinutes = 0): string {{
  const days = calendarDays(learnedAt, now, utcOffsetMinutes)
  if (days === 0) return "today"
  if (days === 1) return "yesterday"
  if (days < 14) return `${{days}} days ago`
  if (days < 60) return `${{Math.floor(days / 7)}} weeks ago`
  return `${{Math.floor(days / 30)}} months ago`
}}

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December"]

/** `PromptClock.dayLine` — "Monday, 28 September 2026", in the learner's zone. */
export function dayLine(at: Date, utcOffsetMinutes = 0): string {{
  const d = new Date(at.getTime() + utcOffsetMinutes * 60_000)
  return `${{WEEKDAYS[d.getUTCDay()]}}, ${{d.getUTCDate()}} ${{MONTHS[d.getUTCMonth()]}} ${{d.getUTCFullYear()}}`
}}

/** `ConversationEngine.expressionBudget(fluentTurns:)`. */
export function expressionBudget(fluentTurns: number): number {{
  return Math.min(14, Math.max(6, fluentTurns))
}}

/** `CoachingLanguage.contract` — empty when the two languages coincide. */
export function coachingContract(target: string, native: string): string {{
  const targetName = englishName(target)
  const nativeName = englishName(native)
  if (targetName === nativeName) return ""
  return `{contract}`
}}

const REGISTER_COMMON = {J(reg_common)}
const REGISTER_KO = {J(reg_extra["ko"])}
const REGISTER_JA = {J(reg_extra["ja"])}

/** `ConversationEngine.registerGuard` — Korean and Japanese only. */
export function registerGuard(targetLanguage: string): string {{
  switch (base(targetLanguage)) {{
    case "ko": return REGISTER_COMMON + REGISTER_KO
    case "ja": return REGISTER_COMMON + REGISTER_JA
    default: return ""
  }}
}}

/** `ConversationEngine.unspacedExpressionNote` — for a target without spaces. */
export function unspacedExpressionNote(targetLanguage: string): string {{
  if (writesSpaces(targetLanguage)) return ""
  return {J(une_parts[0])} + englishName(targetLanguage) + {J(une_parts[1])}
}}

/** One remembered line, as the summary call numbers it (`PersonaNote`). */
export interface RememberedNote {{
  text: string
  /** "fact" | "now" (`PersonaNote.Kind.rawValue`). */
  kind: string
  learnedAt: Date
}}

/** One hand move on a line's share rung (`UserPersona.ShareCorrection`). */
export interface ShareCorrection {{
  text: string
  /** "nothing" | "gist" | "all" (`PersonaNote.Share.rawValue`). */
  from: string
  to: string
}}

/** `ConversationEngine.summarySystemPrompt`, verbatim. */
export function summarySystemPrompt(opts: {{
  targetLanguage: string
  nativeLanguage: string
  profile: unknown
  knownAboutUser?: string[]
  rememberedNotes?: RememberedNote[]
  shareCorrections?: ShareCorrection[]
  expressionBudget?: number
  now?: Date
  /** When the talk happened (a rescued summary runs days later). */
  talkDate?: Date
  /** The learner's UTC offset in minutes, for calendar days. */
  utcOffsetMinutes?: number
  /** The client-built relationship register exception ("" when none). */
  relationshipRegisterLine?: string
  /** The client-built polite-setting exception, Korean ("" when none). */
  politeSettingLine?: string
}}): string {{
  const languageName = englishName(opts.targetLanguage)
  const nativeName = englishName(opts.nativeLanguage)
  const contract = coachingContract(opts.targetLanguage, opts.nativeLanguage)
  const profileJSON = JSON.stringify(opts.profile ?? {{}})
  const now = opts.now ?? new Date()
  const utcOffset = opts.utcOffsetMinutes ?? 0
  const known = opts.knownAboutUser ?? []
  const notes = opts.rememberedNotes ?? []
  const corrections = opts.shareCorrections ?? []
  const expressionBudget = opts.expressionBudget ?? 6
  // Hand-ported list blocks (pinned to the Swift expressions by the generator).
  const knownBlock = known.length === 0 ? "(nothing yet)" : known.map((k) => `- ${{k}}`).join("\\n")
  const rememberedBlock = notes.length === 0 ? "(nothing yet)"
    : notes.map((n, i) => `${{i + 1}}. (${{age(n.learnedAt, now, utcOffset)}}, ${{n.kind}}) ${{n.text}}`).join("\\n")
  const correctionsBlock = corrections.length === 0 ? "(no corrections yet)"
    : corrections.map((c) => `- ${{c.from}} → ${{c.to}}: ${{c.text}}`).join("\\n")
  return `{summary}`
}}
''')
print(f"wrote {OUT.relative_to(ROOT)} from {REF} ({len(summary)} chars of prompt)")
