package com.roro.futurevoice.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import com.roro.futurevoice.data.BookExport
import kotlinx.coroutines.launch

/**
 * The ⋯ on a book page: take this book off the phone.
 *
 * Both book types come through the same [BookDocument], so this menu is the
 * same on both pages and neither knows which renderer it is asking for. PDF
 * to annotate on a tablet or print; Markdown to paste into whatever the
 * learner already keeps notes in.
 *
 * The document is built LAZILY, when a format is picked: building it walks
 * the whole transcript, and a book page must not pay that to draw a toolbar.
 */
@Composable
fun BookExportMenu(document: () -> BookDocument) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }, enabled = !working) {
        Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.export))
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.print_or_save_as_pdf)) },
            leadingIcon = { Icon(Icons.Filled.PictureAsPdf, contentDescription = null) },
            onClick = {
                open = false; working = true
                scope.launch {
                    // The print sheet IS the destination picker — nothing to
                    // share afterwards, because the sheet writes the file.
                    runCatching { BookExport.printPdf(context, document()) }
                    working = false
                }
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.markdown)) },
            leadingIcon = { Icon(Icons.Filled.Notes, contentDescription = null) },
            onClick = {
                open = false; working = true
                scope.launch {
                    runCatching { BookExport.writeMarkdown(context, document()) }
                        .onSuccess { BookExport.share(context, it, "text/markdown") }
                    working = false
                }
            },
        )
    }
}
