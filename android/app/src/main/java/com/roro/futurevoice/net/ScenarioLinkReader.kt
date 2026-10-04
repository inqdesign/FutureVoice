package com.roro.futurevoice.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Fetches a linked page FROM THE PHONE and hands the model its text (iOS
 * `ScenarioLinkReader`, `c06a5cf`). Gemini's own `url_context` fetcher is
 * refused by the sites a situation most often links to — measured
 * 2026-10-01 on a LinkedIn job posting: `URL_RETRIEVAL_STATUS_ERROR` with the
 * URL tool alone and with search beside it — while the same URL fetched as a
 * browser returns the whole posting. The learner's own phone asking for a
 * public page is what opening it in a browser does, so the page is read here
 * and `url_context` stays only for a page this cannot read (a login wall, a
 * script-only page, no network).
 *
 * The request is iOS's byte for byte — Safari's User-Agent and Accept — so
 * the two platforms are answered the same way by the same sites.
 */
object ScenarioLinkReader {
    /** Enough for any posting or listing; longer is navigation and "similar jobs". */
    const val MAX_CHARACTERS = 30_000
    /** Under this, what came back is a wall or a shell, not the page. */
    const val MIN_CHARACTERS = 300
    private const val MAX_BYTES = 3L * 1024 * 1024
    private const val USER_AGENT =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).followRedirects(true).build()
    }

    private class Fetched(val code: Int, val mime: String, val finalPath: String, val body: ByteArray?)

    /** The page's readable text, or null when it could not be read. */
    suspend fun text(link: String): String? = withContext(Dispatchers.IO) {
        val url = link.trim()
        val scheme = url.substringBefore("://", "").lowercase()
        if (scheme != "https" && scheme != "http") return@withContext null
        val request = runCatching {
            Request.Builder().url(url)
                .header("User-Agent", USER_AGENT)
                // Safari's own Accept, byte for byte: LinkedIn answers an
                // unusual one with its bot status (999) about half the time.
                .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .header("Accept-Language", java.util.Locale.getDefault().toLanguageTag())
                .get().build()
        }.getOrNull() ?: return@withContext null

        fun fetch(): Fetched? = runCatching {
            client.newCall(request).execute().use { resp ->
                val len = resp.body.contentLength()
                val bytes = if (resp.isSuccessful && len <= MAX_BYTES) {
                    resp.body.source().let { src ->
                        src.request(MAX_BYTES + 1)
                        if (src.buffer.size > MAX_BYTES) null else src.buffer.readByteArray()
                    }
                } else null
                Fetched(resp.code, resp.body.contentType()?.let { "${it.type}/${it.subtype}" }?.lowercase() ?: "text/html",
                    resp.request.url.encodedPath.lowercase(), bytes)
            }
        }.getOrNull()

        var got = fetch()
        // 999 is LinkedIn's "looks automated"; a second ask usually passes.
        if (got?.code == 999) {
            delay(800)
            got = fetch()
        }
        val page = got ?: return@withContext null
        if (page.code !in 200..299) return@withContext null
        val bytes = page.body ?: return@withContext null
        val mime = page.mime
        if (!(mime.startsWith("text/") || mime.contains("html") || mime.contains("xml"))) return@withContext null
        // A login wall answers 200 at its own address.
        if (listOf("/authwall", "/login", "/signin", "/checkpoint").any { page.finalPath.startsWith(it) }) {
            return@withContext null
        }
        val raw = String(bytes, Charsets.UTF_8)
        val text = if (mime.contains("html") || mime.contains("xml")) readable(raw) else raw
        val trimmed = text.trim()
        if (trimmed.length < MIN_CHARACTERS) null else trimmed.take(MAX_CHARACTERS)
    }

    /**
     * Title, description and the visible text of an HTML page, one block per
     * line. Deliberately crude — the model reads it, and a model reads a page
     * with its menus left in perfectly well; what it cannot read is script
     * and markup.
     */
    fun readable(html: String): String {
        val parts = ArrayList<String>()
        firstMatch("<title[^>]*>(.*?)</title>", html)?.let { parts += "Title: " + decode(it) }
        firstMatch("<meta[^>]+(?:name|property)=[\"'](?:og:)?description[\"'][^>]*content=[\"']([^\"']*)[\"']", html)
            ?.let { parts += "Description: " + decode(it) }
        var body = html
        for (tag in listOf("script", "style", "noscript", "svg", "template", "head")) {
            body = Regex("<$tag\\b[^>]*>[\\s\\S]*?</$tag>", RegexOption.IGNORE_CASE).replace(body, " ")
        }
        body = Regex("<!--[\\s\\S]*?-->").replace(body, " ")
        body = Regex("<(?:br|/p|/div|/li|/h[1-6]|/tr|/section|/article|/ul|/ol)\\b[^>]*>", RegexOption.IGNORE_CASE)
            .replace(body, "\n")
        body = Regex("<li\\b[^>]*>", RegexOption.IGNORE_CASE).replace(body, "\n• ")
        body = Regex("<[^>]+>").replace(body, " ")
        val lines = decode(body).split(Regex("\\r\\n|\\r|\\n"))
            .map { Regex("[ \\t\\u00A0]+").replace(it, " ").trim() }
            .filter { it.isNotEmpty() && it != "•" }
        parts += lines
        return parts.joinToString("\n")
    }

    private fun firstMatch(pattern: String, s: String): String? {
        val m = Regex(pattern, setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)).find(s) ?: return null
        return m.groupValues.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }
    }

    private val named = mapOf(
        "amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ",
        "ndash" to "–", "mdash" to "—", "hellip" to "…", "rsquo" to "’", "lsquo" to "‘",
        "rdquo" to "”", "ldquo" to "“", "bull" to "•", "middot" to "·", "euro" to "€",
    )

    internal fun decode(s: String): String {
        if (!s.contains('&')) return s
        return Regex("&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);").replace(s) { m ->
            val name = m.groupValues[1]
            when {
                name.startsWith("#x") || name.startsWith("#X") ->
                    name.drop(2).toIntOrNull(16)?.let { codePoint(it) } ?: m.value
                name.startsWith("#") -> name.drop(1).toIntOrNull()?.let { codePoint(it) } ?: m.value
                else -> named[name.lowercase()] ?: m.value
            }
        }
    }

    private fun codePoint(v: Int): String? =
        if (Character.isValidCodePoint(v)) String(Character.toChars(v)) else null
}
