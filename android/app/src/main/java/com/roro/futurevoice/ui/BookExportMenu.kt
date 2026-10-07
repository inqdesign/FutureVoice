package com.roro.futurevoice.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.roro.futurevoice.R
import com.roro.futurevoice.data.BookDocument
import com.roro.futurevoice.data.BookGlossary
import com.roro.futurevoice.data.BookExport
import kotlinx.coroutines.launch

/**
 * The ⋯ on a book page: take this book off the phone.
 *
 * Both book types come through the same [BookDocument], so this menu is the
 * same on both pages and neither knows which renderer it is asking for. The
 * PDF is the workbook — to study with a pen, annotate on a tablet or print;
 * Markdown to paste into whatever the learner already keeps notes in.
 *
 * The document is built LAZILY, when a format is picked: building it walks
 * the whole transcript, and a book page must not pay that to draw a toolbar.
 */
@Composable
fun BookExportMenu(
    document: () -> BookDocument,
    nativeLanguage: String = "en",
    targetLanguage: String = "en",
    /** The book's own rows under the export pair — Archive / Unarchive and
     *  Delete, as iOS's ⋯ menu holds them. Given a `close` to call first. */
    extra: (@Composable (close: () -> Unit) -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }, enabled = !working) {
        Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.export))
    }
    com.roro.futurevoice.ui.brand.IosDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        // The workbook — writing space, answers at the back, index tabs
        // ([com.roro.futurevoice.data.WorkbookPdf]). It is the only PDF there
        // is (iOS 25e4d8e2): the plain reader layout sat beside it as "Print
        // or save as PDF" while the redesign hid under a second row.
        com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
            text = { Text(stringResource(R.string.pdf)) },
            leadingIcon = { Icon(Icons.Filled.PictureAsPdf, contentDescription = null) },
            onClick = {
                open = false; working = true
                scope.launch {
                    runCatching {
                        val doc = withGlossary(context, document(), nativeLanguage, targetLanguage)
                        BookExport.writePdf(context,
                            if (doc.language.isEmpty()) doc.copy(language = targetLanguage) else doc)
                    }.onSuccess { BookExport.share(context, it, "application/pdf") }
                    working = false
                }
            },
        )
        com.roro.futurevoice.ui.brand.IosDropdownMenuItem(
            text = { Text(stringResource(R.string.markdown)) },
            leadingIcon = { Icon(Icons.Filled.Notes, contentDescription = null) },
            onClick = {
                open = false; working = true
                scope.launch {
                    runCatching { BookExport.writeMarkdown(context, withGlossary(context, document(), nativeLanguage, targetLanguage)) }
                        .onSuccess { BookExport.share(context, it, "text/markdown") }
                    working = false
                }
            },
        )
        extra?.invoke { open = false }
    }
}

/**
 * The glossary is looked up when a format is picked, never when the page
 * draws: it is a network read, and it is bounded inside [BookGlossary] so a
 * slow dictionary costs the glossary and not the export.
 */
private suspend fun withGlossary(context: android.content.Context, doc: BookDocument,
                                 native: String, target: String): BookDocument {
    val section = runCatching { BookGlossary.section(context, doc, native, target) }.getOrNull()
    return if (section == null) doc else doc.copy(sections = doc.sections + section)
}
