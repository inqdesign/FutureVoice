package com.roro.futurevoice.data

import android.content.Context
import android.content.Intent
import android.print.PrintAttributes
import android.print.PrintManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume

/**
 * Taking a [BookDocument] off the phone.
 *
 * The two formats leave by different doors, and that is Android's shape
 * rather than a compromise:
 *
 * - **Markdown** is written to a file and handed to the share sheet.
 * - **PDF** goes through the SYSTEM PRINT flow. `PrintDocumentAdapter`'s
 *   result callbacks have package-private constructors, so an app cannot
 *   drive the adapter itself and write the file directly — the documented
 *   route is `PrintManager`, where the sheet's own "Save as PDF" writes it
 *   wherever the learner says. That sheet also prints, which is half of what
 *   the PDF was for anyway.
 *
 * Either way the layout is done by a WebView from [BookDocument.html], which
 * is the whole reason the document is authored as HTML: it is the only thing
 * on Android that flows arbitrary-length text across A4 pages with real,
 * selectable text and no hand-rolled pagination — the same bargain iOS makes
 * with `UIMarkupTextPrintFormatter`.
 */
object BookExport {

    /** Everything lands in one directory so a share can be cleaned up later. */
    private fun outDir(context: Context): File =
        File(context.cacheDir, "book-export").apply { mkdirs() }

    suspend fun writeMarkdown(context: Context, doc: BookDocument): File =
        withContext(Dispatchers.IO) {
            File(outDir(context), doc.filename + ".md").apply { writeText(doc.markdown) }
        }

    /**
     * Lay the book out and hand it to the system print sheet, where "Save as
     * PDF" is one of the destinations. The WebView is held by the adapter for
     * the life of the job, so it is kept alive in a field rather than left to
     * be collected mid-layout — a print that loses its source view produces a
     * blank page and no error.
     */
    @Suppress("StaticFieldLeak")
    private var printing: WebView? = null

    suspend fun printPdf(context: Context, doc: BookDocument) = withContext(Dispatchers.Main) {
        val web = WebView(context)
        printing = web
        loadHtml(web, doc.html)
        val manager = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
        manager.print(
            doc.filename,
            web.createPrintDocumentAdapter(doc.filename),
            PrintAttributes.Builder()
                .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                .build(),
        )
    }

    private suspend fun loadHtml(web: WebView, html: String) =
        suspendCancellableCoroutine { cont ->
            web.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    if (!cont.isCompleted) cont.resume(Unit)
                }
            }
            // A null base URL keeps the page inert — the document is
            // self-contained (no images, no scripts) and must stay that way.
            web.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
        }

    /** Hand the file to whatever the learner keeps notes in. */
    fun share(context: Context, file: File, mime: String) {
        val uri = FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, null))
    }
}
