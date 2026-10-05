package com.roro.futurevoice.data

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Taking a [BookDocument] off the phone: written to a file and handed to the
 * share sheet. The PDF is the workbook ([WorkbookPdf]) — the plain reader
 * layout that went through the system print sheet was deleted with iOS
 * 25e4d8e2; a real file is also the only thing that keeps the workbook's
 * index-tab links.
 */
object BookExport {

    /** Everything lands in one directory so a share can be cleaned up later. */
    private fun outDir(context: Context): File =
        File(context.cacheDir, "book-export").apply { mkdirs() }

    suspend fun writeMarkdown(context: Context, doc: BookDocument): File =
        withContext(Dispatchers.IO) {
            File(outDir(context), doc.filename + ".md").apply { writeText(doc.markdown) }
        }

    /** The book's one PDF — the workbook, laid out for a pen. */
    suspend fun writePdf(context: Context, doc: BookDocument): File =
        withContext(Dispatchers.Default) {
            val bytes = WorkbookPdf(context, doc).pdfData()
            withContext(Dispatchers.IO) {
                File(outDir(context), doc.filename + ".pdf").apply { writeBytes(bytes) }
            }
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
