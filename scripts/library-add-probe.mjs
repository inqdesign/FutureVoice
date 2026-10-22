// Usage: node scripts/library-add-probe.mjs scripts/library-add-cases.json
// Runs library-add's judge prompt, read out of the function source, on
// labelled cases (typos, made-up words, names, phrases filed as words) and
// applies the function's own code guards. Re-run before touching the prompt.
// Baseline 2026-10-22, 3.6-flash medium: 0/57 wrong over three runs.
import fs from "fs"
const src = fs.readFileSync(new URL("../supabase/functions/library-add/index.ts", import.meta.url), "utf8")
const j = src.indexOf("async function judge")
const fnBody = src.slice(src.indexOf("  const lang =", j), src.indexOf("  try {", j))
const key = Object.fromEntries(fs.readFileSync(new URL("../gateway/.dev.vars", import.meta.url),"utf8").split("\n").filter(l=>l.includes("=")).map(l=>[l.split("=")[0], l.slice(l.indexOf("=")+1).trim().replace(/^"|"$/g,"")])).GEMINI_API_KEY
const names = {en:"English",ko:"Korean",ja:"Japanese",de:"German",es:"Spanish"}
function system(text, kind, target) {
  const languageName = c => names[c]
  // eslint-disable-next-line no-new-func
  const f = new Function("text","kind","target","languageName", fnBody + "\nreturn system")
  return f(text, kind, target, languageName)
}
const cases = JSON.parse(fs.readFileSync(process.argv[2],"utf8"))
let bad = 0
await Promise.all(cases.map(async ([text, kind, target, want]) => {
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${key}`, {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({system_instruction:{parts:[{text:system(text,kind,target)}]},contents:[{role:"user",parts:[{text}]}],generationConfig:{maxOutputTokens:2048,thinkingConfig:{thinkingLevel:"medium"},responseMimeType:"application/json"}})})
  const p = await r.json(); const out = p?.candidates?.[0]?.content?.parts?.map(x=>x.text).join("") ?? JSON.stringify(p).slice(0,200)
  let v; try { v = JSON.parse(out.slice(out.indexOf("{"), out.lastIndexOf("}")+1)) } catch { v = {verdict:"PARSE"} }
  if (v.verdict==="ok" && v.form==="respelled") v.verdict="typo"
  if (v.verdict==="ok" && kind==="word" && /\s/.test(v.headword||"")) v.verdict="wrong_kind"
  const ok = want.split("|").includes(v.verdict)
  if (!ok) bad++
  console.log(`${ok?"  ":"✗ "}${target} ${kind.padEnd(10)} ${text.padEnd(28)} want=${want.padEnd(11)} got=${v.verdict} ${v.headword||v.suggestion||""} ${v.level||""}`)
}))
console.log(`wrong: ${bad}/${cases.length}`)
