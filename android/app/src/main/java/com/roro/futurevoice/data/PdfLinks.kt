package com.roro.futurevoice.data

import java.io.ByteArrayOutputStream

/**
 * Internal links added to a finished PDF — what makes the workbook's index
 * tabs tappable in a tablet notes app, the way iOS's
 * `UIGraphicsPDFRendererContext.setDestinationWithName` does.
 *
 * `android.graphics.pdf.PdfDocument` has no link API at all, so the links are
 * appended afterwards as a standard INCREMENTAL UPDATE: each page that gets a
 * link is re-emitted with an `/Annots` array, the link annotations are new
 * objects, and a new xref section points back at the original one with
 * `/Prev`. Nothing in the original bytes is touched.
 *
 * Any surprise in the input (a cross-reference stream, a page that already
 * has annotations, a tree it can't walk) returns the input unchanged: the
 * tabs are still printed, they just aren't links. A link is a convenience; a
 * broken file is not an acceptable price for it.
 */
object PdfLinks {

    /** A rectangle on [page] (top-left origin, points) that jumps to [targetPage]. */
    data class Link(
        val page: Int,
        val left: Float, val top: Float, val right: Float, val bottom: Float,
        val targetPage: Int,
    )

    fun add(pdf: ByteArray, pageHeight: Float, links: List<Link>): ByteArray {
        if (links.isEmpty()) return pdf
        return runCatching { addOrThrow(pdf, pageHeight, links) }.getOrElse { pdf }
    }

    private class Malformed(msg: String) : Exception(msg)

    private fun addOrThrow(pdf: ByteArray, pageHeight: Float, links: List<Link>): ByteArray {
        // ISO-8859-1 maps every byte to one char, so string offsets ARE byte offsets.
        val text = String(pdf, Charsets.ISO_8859_1)
        val startxref = Regex("startxref\\s+(\\d+)\\s+%%EOF\\s*$").find(text)
            ?.groupValues?.get(1)?.toInt() ?: throw Malformed("no startxref")
        if (!text.startsWith("xref", startxref)) throw Malformed("xref stream")

        val offsets = HashMap<Int, Int>()
        val trailerAt = text.indexOf("trailer", startxref)
        if (trailerAt < 0) throw Malformed("no trailer")
        val table = text.substring(startxref + 4, trailerAt).trim().lines().map { it.trim() }
            .filter { it.isNotEmpty() }
        var i = 0
        while (i < table.size) {
            val head = table[i].split(Regex("\\s+"))
            if (head.size != 2) throw Malformed("xref subsection")
            val first = head[0].toInt(); val count = head[1].toInt()
            for (k in 0 until count) {
                val row = table[i + 1 + k].split(Regex("\\s+"))
                if (row.size >= 3 && row[2] == "n") offsets[first + k] = row[0].toInt()
            }
            i += 1 + count
        }
        val trailer = dictAt(text, text.indexOf("<<", trailerAt))
        val size = Regex("/Size\\s+(\\d+)").find(trailer)?.groupValues?.get(1)?.toInt()
            ?: throw Malformed("no size")
        val root = ref(trailer, "Root") ?: throw Malformed("no root")
        val info = ref(trailer, "Info")

        fun objectDict(n: Int): String {
            val at = offsets[n] ?: throw Malformed("object $n missing")
            val open = text.indexOf("<<", at)
            val head = text.substring(at, open)
            if (!Regex("^\\s*$n\\s+0\\s+obj\\s*$").matches(head)) throw Malformed("object $n header")
            return dictAt(text, open)
        }

        // Pages in document order: walk the tree from the catalog.
        val pages = ArrayList<Int>()
        fun walk(n: Int, depth: Int) {
            if (depth > 32) throw Malformed("tree too deep")
            val d = objectDict(n)
            if (Regex("/Type\\s*/Pages(?![A-Za-z])").containsMatchIn(d)) {
                val kids = Regex("/Kids\\s*\\[([^\\]]*)]").find(d)?.groupValues?.get(1)
                    ?: throw Malformed("no kids")
                Regex("(\\d+)\\s+0\\s+R").findAll(kids).forEach { walk(it.groupValues[1].toInt(), depth + 1) }
            } else if (Regex("/Type\\s*/Page(?![A-Za-z])").containsMatchIn(d)) {
                pages.add(n)
            } else throw Malformed("not a page")
        }
        val pagesRoot = ref(objectDict(root), "Pages") ?: throw Malformed("no pages")
        walk(pagesRoot, 0)

        val byPage = links.filter { it.page in pages.indices && it.targetPage in pages.indices }
            .groupBy { it.page }
        if (byPage.isEmpty()) return pdf

        val out = ByteArrayOutputStream()
        out.write(pdf)
        var cursor = pdf.size
        if (pdf.last() != '\n'.code.toByte()) { out.write('\n'.code); cursor += 1 }
        val written = sortedMapOf<Int, Int>()
        fun emit(n: Int, body: String) {
            written[n] = cursor
            val bytes = "$n 0 obj\n$body\nendobj\n".toByteArray(Charsets.ISO_8859_1)
            out.write(bytes); cursor += bytes.size
        }

        var next = size
        for ((pageIndex, pageLinks) in byPage.toSortedMap()) {
            val pageObj = pages[pageIndex]
            val dict = objectDict(pageObj)
            if (dict.contains("/Annots")) throw Malformed("page already annotated")
            val annots = pageLinks.map { link ->
                val n = next++
                val y1 = pageHeight - link.bottom
                val y2 = pageHeight - link.top
                emit(n, "<< /Type /Annot /Subtype /Link /Rect [${f(link.left)} ${f(y1)} ${f(link.right)} ${f(y2)}]" +
                    " /Border [0 0 0] /Dest [${pages[link.targetPage]} 0 R /Fit] >>")
                n
            }
            val inner = dict.substring(0, dict.length - 2).trimEnd()
            emit(pageObj, "$inner\n/Annots [${annots.joinToString(" ") { "$it 0 R" }}] >>")
        }

        val xrefAt = cursor
        val xref = StringBuilder("xref\n")
        // One subsection per contiguous run of object numbers.
        val numbers = written.keys.toList()
        var s = 0
        while (s < numbers.size) {
            var e = s
            while (e + 1 < numbers.size && numbers[e + 1] == numbers[e] + 1) e++
            xref.append("${numbers[s]} ${e - s + 1}\n")
            for (k in s..e) xref.append(String.format(java.util.Locale.US, "%010d 00000 n \n", written[numbers[k]]))
            s = e + 1
        }
        xref.append("trailer\n<< /Size $next /Root $root 0 R")
        if (info != null) xref.append(" /Info $info 0 R")
        xref.append(" /Prev $startxref >>\nstartxref\n$xrefAt\n%%EOF\n")
        out.write(xref.toString().toByteArray(Charsets.ISO_8859_1))
        return out.toByteArray()
    }

    private fun f(v: Float): String = String.format(java.util.Locale.US, "%.2f", v)

    private fun ref(dict: String, key: String): Int? =
        Regex("/$key\\s+(\\d+)\\s+0\\s+R").find(dict)?.groupValues?.get(1)?.toInt()

    /** The balanced `<< … >>` starting at [open], strings and comments aside
     *  (a page or trailer dictionary has neither in practice). */
    private fun dictAt(text: String, open: Int): String {
        if (open < 0 || !text.startsWith("<<", open)) throw Malformed("no dict")
        var depth = 0
        var i = open
        while (i < text.length - 1) {
            when {
                text.startsWith("<<", i) -> { depth++; i += 2 }
                text.startsWith(">>", i) -> {
                    depth--; i += 2
                    if (depth == 0) return text.substring(open, i)
                }
                text[i] == '(' -> {
                    // Skip a literal string, honouring escapes and nesting.
                    var level = 0
                    while (i < text.length) {
                        val c = text[i]
                        if (c == '\\') { i += 2; continue }
                        if (c == '(') level++
                        if (c == ')') { level--; if (level == 0) { i++; break } }
                        i++
                    }
                }
                else -> i++
            }
        }
        throw Malformed("unbalanced dict")
    }
}
