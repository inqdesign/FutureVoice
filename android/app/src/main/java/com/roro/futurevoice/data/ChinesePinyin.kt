package com.roro.futurevoice.data

import java.text.Normalizer

/**
 * Pinyin over each character of a Chinese line, for drawing above it
 * (`FuriganaText`, through [Furigana.runs]) — port of iOS
 * `ChinesePinyin.swift` (2026-11-20, learner feedback: a learner who can't
 * read 银行 can't say the line).
 *
 * The word's reading comes from the HSK list when the list has the word,
 * else from ICU, then is cut into one syllable per character, guided by
 * each character read on its own. 一 and 不 take the tone they are SAID
 * with (bú qù, yí gè), as textbooks print them. A wrong reading is a display
 * slip, never a grade.
 */
object ChinesePinyin {

    /** Runs over [text] (UTF-16 offsets), one per Han character with its
     *  syllable; everything else plain. */
    fun runs(text: String): List<Furigana.Run> {
        val readings = arrayOfNulls<String>(text.length)
        val tokens = ChineseMorph.words(text)
        for ((t, token) in tokens.withIndex()) {
            val surface = token.surface
            if (surface.none(::isHan)) continue
            val next = tokens.getOrNull(t + 1)?.key
            val word = reading(token, next)
            val parts = split(word, surface)
            if (parts != null) {
                for ((i, part) in parts.withIndex()) if (isHan(surface[i])) readings[token.start + i] = part
            } else if (surface.all(::isHan)) {
                for ((i, ch) in surface.withIndex()) readings[token.start + i] = solo(ch)
            }
        }
        applySandhi(text, readings)
        val out = ArrayList<Furigana.Run>()
        for (i in text.indices) {
            val r = readings[i]
            val last = out.lastOrNull()
            if (r == null && last != null && last.reading == null) {
                out[out.size - 1] = Furigana.Run(last.start, i + 1, null)
            } else {
                out.add(Furigana.Run(i, i + 1, r))
            }
        }
        return out
    }

    // ── The word's reading ──

    /** Words ICU and the list both read wrong in everyday talk. */
    private val fixed = mapOf(
        "这个" to "zhège", "那个" to "nàge", "哪个" to "nǎge", "什么" to "shénme",
        "怎么" to "zěnme", "东西" to "dōngxi", "地方" to "dìfang", "知道" to "zhīdao",
        "谢谢" to "xièxie", "朋友" to "péngyou", "时候" to "shíhou", "喜欢" to "xǐhuan",
        "一点儿" to "yīdiǎnr", "女儿" to "nǚ'ér",
    )

    private val givenBack = listOf("钱", "书", "给", "款", "债", "回", "清")

    private fun reading(token: ChineseMorph.Token, next: String?): String {
        val key = token.key
        if (key == "还") return if (givenBack.any { next?.startsWith(it) == true }) "huán" else "hái"
        fixed[key]?.let { return it }
        CoreVocabulary.listedReading(key, "zh")?.let { listed ->
            val alts = listed.split("・")
            val tok = token.pinyin.lowercase()
            return alts.firstOrNull { it.lowercase() == tok } ?: alts[0]
        }
        return erhua(key, token.pinyin)
    }

    /** 儿 closing a word off the list is the r on the syllable before it
     *  (点儿 diǎnr); listed words keep the list's reading (女儿 nǚ'ér). */
    fun erhua(key: String, pinyin: String): String {
        if (key.length < 2 || !key.endsWith("儿")) return pinyin
        for (tail in listOf("ér", "er")) if (pinyin.endsWith(tail)) return pinyin.dropLast(tail.length) + "r"
        return pinyin
    }

    // ── One syllable per character ──

    /** [word] cut into one piece per character of [surface]; the cut that
     *  agrees with the most characters read on their own wins. */
    fun split(word: String, surface: String): List<String>? {
        val w = word.replace("'", "").replace(" ", "")
        val n = surface.length
        if (n == 1) return listOf(w)
        if (surface.last() == '儿' && w.endsWith("r") && !bare(w.takeLast(2)).endsWith("er")) {
            val head = split(w.dropLast(1), surface.dropLast(1)) ?: return null
            return head + "r"
        }
        val hints = surface.map { bare(solo(it) ?: "") }
        var bestScore = -1
        var best: List<String>? = null
        fun walk(i: Int, at: Int, parts: List<String>, score: Int) {
            if (i == n) {
                if (at == w.length && score > bestScore) { bestScore = score; best = parts }
                return
            }
            val left = n - i - 1
            if (at >= w.length) return
            for (len in 1..minOf(6, w.length - at)) {
                val rest = w.length - at - len
                if (rest < left || (left == 0 && rest != 0)) continue
                val piece = w.substring(at, at + len)
                if (!isSyllableShape(piece) || marks(piece) > 1) continue
                walk(i + 1, at + len, parts + piece, score + if (bare(piece) == hints[i]) 10 else 0)
            }
        }
        walk(0, 0, emptyList(), 0)
        return best
    }

    private fun isSyllableShape(s: String): Boolean {
        val b = bare(s)
        return b.any { it in "aeiouv" } || b == "m" || b == "n" || b == "ng"
    }

    // ── Tone change ──

    private fun applySandhi(text: String, r: Array<String?>) {
        for (i in text.indices) {
            val ch = text[i]
            if (ch != '不' && ch != '一') continue
            val nextTone = r.getOrNull(i + 1)?.let(::tone)
            if (ch == '不') {
                r[i] = if (nextTone == 4) "bú" else "bù"
            } else {
                val prev = text.getOrNull(i - 1)
                val next = text.getOrNull(i + 1)
                val counted = (prev != null && prev in "第十百千万零〇一二三四五六七八九两") ||
                    (next != null && (next in "月号十百千万一二三四五六七八九两" || next.isDigit()))
                r[i] = when {
                    nextTone == null || counted -> "yī"
                    next == '个' -> "yí"
                    nextTone == 4 || nextTone == 5 -> "yí"
                    else -> "yì"
                }
            }
        }
    }

    fun tone(syllable: String): Int {
        for (ch in syllable) {
            if (ch in "āēīōūǖ") return 1
            if (ch in "áéíóúǘ") return 2
            if (ch in "ǎěǐǒǔǚ") return 3
            if (ch in "àèìòùǜ") return 4
        }
        return 5
    }

    private fun marks(s: String) = s.count { it in "āēīōūǖáéíóúǘǎěǐǒǔǚàèìòùǜ" }

    /** Without tone marks, ü as v, lowercased. */
    fun bare(s: String): String {
        val v = s.lowercase().replace("ü", "v").replace("ǖ", "v").replace("ǘ", "v")
            .replace("ǚ", "v").replace("ǜ", "v")
        return Normalizer.normalize(v, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
    }

    // ── A character on its own ──

    private val soloMemo = HashMap<Char, String?>()

    fun solo(ch: Char): String? {
        synchronized(soloMemo) { if (soloMemo.containsKey(ch)) return soloMemo[ch] }
        val s = ch.toString()
        val out = ChineseMorph.pinyinOfCharacter(s).takeIf { it != s && it.isNotEmpty() }
        synchronized(soloMemo) { soloMemo[ch] = out }
        return out
    }

    fun isHan(c: Char): Boolean = c.code in 0x4E00..0x9FFF || c.code in 0x3400..0x4DBF
}
