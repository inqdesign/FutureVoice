package com.roro.futurevoice.ui

import android.content.Intent
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import com.roro.futurevoice.R
import com.roro.futurevoice.data.DayCardStore
import com.roro.futurevoice.ui.brand.DayCard
import com.roro.futurevoice.ui.brand.DayCardData
import com.roro.futurevoice.ui.brand.DayCardFormat
import com.roro.futurevoice.ui.brand.FutureselfTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The day's share card. A running app hands you a card the moment the run is
 * saved; here the card is the DAY's — the summary as a picture.
 *
 * The photo is the PLACE, and that is as precise as it gets: the learner
 * photographs where they are (the camera, because "take it now" is the
 * point), and saving re-encodes, which drops EXIF/GPS. Opening the sheet
 * stores nothing; only a picked photo does.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DayCardSheet(data: DayCardData, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var format by remember { mutableStateOf(DayCardFormat.FEED) }
    var photo by remember { mutableStateOf<Bitmap?>(null) }
    // The headline the card prints. It starts as the day's main talk and can
    // be replaced — the topic of a news talk is a sentence, and the learner
    // is the one who knows what the day was about.
    var headline by remember(data.date) { mutableStateOf(data.topics.firstOrNull().orEmpty()) }
    val theme = remember { FutureselfTheme.stored(context).ordinal }
    LaunchedEffect(data.date) { photo = DayCardStore.photo(context, data.date) }

    val camera = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicturePreview()
    ) { bitmap ->
        if (bitmap != null) {
            photo = bitmap
            DayCardStore.savePhoto(context, data.date, bitmap)
            // Making a card settles the day: a card is what that day WAS.
            DayCardStore.freeze(context, data)
        }
    }
    val cameraPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) camera.launch(null) }
    // A photo already taken is a place too — the camera is the point, but
    // refusing the library would mean a day can only be illustrated live.
    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openInputStream(uri).use {
                android.graphics.BitmapFactory.decodeStream(it)
            }
        }.getOrNull()?.let { bitmap ->
            photo = bitmap
            DayCardStore.savePhoto(context, data.date, bitmap)
            DayCardStore.freeze(context, data)
        }
    }

    val layer = rememberGraphicsLayer()

    // Fully expanded: the card is 450dp tall and a half-height sheet cut it
    // off, so the learner saw a black slab with no footer and no date.
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // "Today's card" is a claim about WHICH day — say it only when it
            // is true, and name the day otherwise.
            val isToday = android.text.format.DateUtils.isToday(data.date)
            Text(
                if (isToday) stringResource(R.string.today_s_card)
                else java.text.SimpleDateFormat("d MMM", java.util.Locale.getDefault())
                    .format(java.util.Date(data.date)),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.fillMaxWidth())
            DayCard(
                data = data.copy(topics = listOfNotNull(headline.takeIf { it.isNotBlank() })),
                photo = photo?.asImageBitmap(), format = format, theme = theme,
                modifier = Modifier.drawWithContent {
                    // Record the card as it is drawn, so the exported picture
                    // is exactly what the learner is looking at.
                    layer.record { this@drawWithContent.drawContent() }
                    drawLayer(layer)
                },
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(format == DayCardFormat.FEED,
                    onClick = { format = DayCardFormat.FEED },
                    label = { Text(stringResource(R.string.feed_4_5)) })
                FilterChip(format == DayCardFormat.SQUARE,
                    onClick = { format = DayCardFormat.SQUARE },
                    label = { Text(stringResource(R.string.square)) })
            }
            // Headline — the day's talks to pick from, or write your own.
            if (data.topics.size > 1) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    data.topics.forEach { t ->
                        FilterChip(headline == t, onClick = { headline = t },
                            label = { Text(t, maxLines = 1) })
                    }
                }
            }
            OutlinedTextField(
                value = headline,
                onValueChange = { headline = it },
                label = { Text(stringResource(R.string.headline)) },
                placeholder = { Text(stringResource(R.string.or_write_your_own)) },
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedButton(
                onClick = { cameraPermission.launch(android.Manifest.permission.CAMERA) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.take_a_photo))
            }
            OutlinedButton(
                onClick = { imagePicker.launch("image/*") },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.choose_a_photo))
            }
            if (photo != null) {
                TextButton(
                    onClick = {
                        photo = null
                        DayCardStore.removePhoto(context, data.date)
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.remove_photo),
                        color = MaterialTheme.colorScheme.error)
                }
            }
            // Said plainly because it is the whole privacy story of this
            // feature: the photo is the place, and nothing else about where
            // the learner was is kept.
            Text(stringResource(R.string.where_you_studied_that_day_the_photo_is_the_place_nothing_el_642592),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(
                onClick = {
                    scope.launch {
                        val raw = layer.toImageBitmap().asAndroidBitmap()
                        // The layer captures at the SCREEN's density; the card
                        // is a feed picture, so it ships at the frame the feed
                        // wants — 1080×1350 (4:5) / 1080×1080 — whatever phone
                        // made it.
                        val targetW = 360 * DayCardFormat.EXPORT_SCALE
                        val targetH = format.height * DayCardFormat.EXPORT_SCALE
                        val bmp = if (raw.width == targetW) raw
                        else Bitmap.createScaledBitmap(raw, targetW, targetH, true)
                        val file = withContext(Dispatchers.IO) {
                            val dir = File(context.cacheDir, "share").apply { mkdirs() }
                            File(dir, "daycard.png").also { f ->
                                f.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                            }
                        }
                        val uri = FileProvider.getUriForFile(
                            context, "${context.packageName}.fileprovider", file)
                        DayCardStore.freeze(context, data)
                        context.startActivity(Intent.createChooser(
                            Intent(Intent.ACTION_SEND).apply {
                                type = "image/png"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, null))
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text(stringResource(R.string.share)) }
        }
    }
}
