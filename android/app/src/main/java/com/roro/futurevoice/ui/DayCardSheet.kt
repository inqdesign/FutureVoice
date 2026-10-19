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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import com.roro.futurevoice.ui.brand.IosButton as Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import com.roro.futurevoice.ui.brand.IosOutlinedButton as OutlinedButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.drawWithContent
import com.roro.futurevoice.ui.brand.IosGlassButton
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.layout.layout
import androidx.core.content.FileProvider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import com.roro.futurevoice.ui.rememberModalBottomSheetState
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
    /** The field holds the learner's OWN words only (iOS `headlineText`). */
    var ownText by remember(data.date) { mutableStateOf("") }
    val targetLanguage = remember { com.roro.futurevoice.data.LanguageScope.active(context) }
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", 0)
            .getString("futurevoice.nativeLanguage", null) ?: "en"
    }
    val theme = FutureselfTheme.stored(context).ordinal
    LaunchedEffect(data.date) { photo = DayCardStore.photo(context, data.date) }

    // The full-size shot, not `TakePicturePreview` — that one hands back the
    // camera's thumbnail (a few hundred pixels), which is what a 1080-wide
    // card in an Instagram story showed as mush.
    val cameraUri = remember {
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider",
            File(dir, "daycard-camera.jpg"))
    }
    val camera = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { taken ->
        if (!taken) return@rememberLauncherForActivityResult
        DayCardStore.decodeUpright(context, cameraUri)?.let { bitmap ->
            photo = bitmap
            DayCardStore.savePhoto(context, data.date, bitmap)
            // Making a card settles the day: a card is what that day WAS.
            DayCardStore.freeze(context, data)
        }
    }
    val cameraPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) camera.launch(cameraUri) }
    // A photo already taken is a place too — the camera is the point, but
    // refusing the library would mean a day can only be illustrated live.
    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        DayCardStore.decodeUpright(context, uri)?.let { bitmap ->
            photo = bitmap
            DayCardStore.savePhoto(context, data.date, bitmap)
            DayCardStore.freeze(context, data)
        }
    }

    val layer = rememberGraphicsLayer()

    /** The card as the share sheet ships it: the layer captures at the
     *  SCREEN's density, but a feed picture goes out at the frame the feed
     *  wants — 1080×1350 (4:5) / 1080×1080 — whatever phone made it. */
    suspend fun renderCard(): Bitmap {
        val raw = layer.toImageBitmap().asAndroidBitmap()
        val targetW = 360 * DayCardFormat.EXPORT_SCALE
        val targetH = format.height * DayCardFormat.EXPORT_SCALE
        return if (raw.width == targetW) raw
        else Bitmap.createScaledBitmap(raw, targetW, targetH, true)
    }

    /** The card into the share sheet (iOS's toolbar ShareLink). */
    fun share() {
        scope.launch {
            val bmp = renderCard()
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
    }

    // Where "Save to Photos" stands for the card as it is drawn NOW; any
    // change to the card puts it back to idle, since that is a new picture.
    var saveState by remember { mutableStateOf(SaveState.IDLE) }
    var photosDenied by remember { mutableStateOf(false) }
    LaunchedEffect(format, headline, photo) { saveState = SaveState.IDLE }
    fun save() {
        saveState = SaveState.SAVING
        scope.launch {
            val ok = runCatching { saveToGallery(context, renderCard()) }.getOrDefault(false)
            saveState = if (ok) SaveState.SAVED else SaveState.IDLE
        }
    }
    // Android 8–9 only: writing to the shared gallery needs the old storage
    // permission there; 10+ inserts through MediaStore with none.
    val storagePermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) save() else photosDenied = true }
    if (photosDenied) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { photosDenied = false },
            title = { Text(stringResource(R.string.allow_access_to_photos)) },
            text = { Text(stringResource(R.string.turn_on_photos_for_nawana_in_settings_to_save_the_card)) },
            confirmButton = {
                TextButton(onClick = {
                    photosDenied = false
                    context.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.fromParts("package", context.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text(stringResource(R.string.open_settings)) }
            },
            dismissButton = {
                TextButton(onClick = { photosDenied = false }) { Text(stringResource(R.string.cancel)) }
            })
    }

    // Fully expanded: the card is 450dp tall and a half-height sheet cut it
    // off, so the learner saw a black slab with no footer and no date.
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, dragHandle = null,
        containerColor = com.roro.futurevoice.ui.brand.AppSurfaces.ground) {
        // iOS: an inline nav bar — Done leading, the title centred, Share
        // trailing. "Today's card" is a claim about WHICH day — say it only
        // when it is true, and name the day otherwise.
        val isToday = android.text.format.DateUtils.isToday(data.date)
        SheetHeader(
            title = if (isToday) stringResource(R.string.today_s_card)
                else java.text.SimpleDateFormat(android.text.format.DateFormat.getBestDateTimePattern(java.util.Locale.getDefault(), "MMMd"), java.util.Locale.getDefault())
                    .format(java.util.Date(data.date)),
            leading = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss) },
            trailing = {
                IosGlassButton(onClick = { share() }, circle = true) {
                    androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Outlined.IosShare,
                        contentDescription = stringResource(R.string.share),
                        tint = MaterialTheme.colorScheme.primary)
                }
            },
            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 8.dp),
        )
        // iOS `DayCardSheet` is a Form: the card, the format picker, then
        // three grouped sections — Save to Photos · Headline · Photo.
        Column(
            Modifier.fillMaxWidth().bottomBarInsets().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 32.dp),
        ) {
            // The card is LAID OUT at its export size — 360dp at density 3,
            // 1080 px wide — and only DRAWN smaller to fit the screen. Laid
            // out at the screen's size it was captured at ~2.6x and upscaled
            // (soft), and on a phone narrower than 360dp + gutters it was
            // squeezed to the width and then stretched back to 4:5.
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
                val cardW = DayCardFormat.FEED.width
                val shownW = minOf(maxWidth, cardW.dp)
                val shownH = shownW * (format.height.toFloat() / cardW)
                val pxW = cardW * DayCardFormat.EXPORT_SCALE
                val pxH = format.height * DayCardFormat.EXPORT_SCALE
                // Same corner and shadow as iOS's preview; the export records
                // inside the clip, so the shared picture stays square-cornered
                // like iOS's render.
                Box(Modifier.align(Alignment.Center).padding(vertical = 8.dp).size(shownW, shownH)
                    .shadow(10.dp, androidx.compose.foundation.shape.RoundedCornerShape(26.dp),
                        ambientColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.18f),
                        spotColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.18f))
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(26.dp))) {
                    androidx.compose.runtime.CompositionLocalProvider(
                        androidx.compose.ui.platform.LocalDensity provides
                            androidx.compose.ui.unit.Density(DayCardFormat.EXPORT_SCALE.toFloat(), 1f),
                    ) {
                        DayCard(
                            data = data.copy(topics = listOfNotNull(headline.takeIf { it.isNotBlank() })),
                            photo = photo?.asImageBitmap(), format = format, theme = theme,
                            modifier = Modifier.layout { measurable, constraints ->
                                val placeable = measurable.measure(
                                    androidx.compose.ui.unit.Constraints.fixed(pxW, pxH))
                                val w = constraints.maxWidth
                                val h = constraints.maxHeight
                                layout(w, h) {
                                    placeable.placeWithLayer(0, 0) {
                                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0f)
                                        scaleX = w.toFloat() / pxW
                                        scaleY = h.toFloat() / pxH
                                    }
                                }
                            }.drawWithContent {
                                // Record the card as it is drawn, at full size, so
                                // the exported picture is exactly what the learner
                                // is looking at.
                                layer.record { this@drawWithContent.drawContent() }
                                drawLayer(layer)
                            },
                        )
                    }
                }
            }
            com.roro.futurevoice.ui.brand.IosSegmented(
                options = listOf(stringResource(R.string.feed_4_5), stringResource(R.string.square)),
                selected = if (format == DayCardFormat.FEED) 0 else 1,
                onSelect = { format = if (it == 0) DayCardFormat.FEED else DayCardFormat.SQUARE },
                modifier = Modifier.fillMaxWidth().padding(top = 20.dp),
            )

            // The card straight into the gallery (iOS `704cc4a`). The share
            // sheet's own "save" is easy to miss among the apps, and keeping
            // the day is the commonest thing to do with it.
            FormSection(header = null) {
                FormActionRow(
                    icon = if (saveState == SaveState.SAVED) androidx.compose.material.icons.Icons.Filled.Check
                        else androidx.compose.material.icons.Icons.Filled.Download,
                    text = stringResource(if (saveState == SaveState.SAVED) R.string.saved_to_photos
                        else R.string.save_to_photos),
                    enabled = saveState == SaveState.IDLE,
                ) {
                    val needsPermission = android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q &&
                        androidx.core.content.ContextCompat.checkSelfPermission(context,
                            android.Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                        android.content.pm.PackageManager.PERMISSION_GRANTED
                    if (needsPermission) storagePermission.launch(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    else save()
                }
            }

            // Headline — the day's talks to pick from (the automatic pick is
            // the first), then a field for the learner's OWN words. A picked
            // talk shows as a checkmark on its row, never in the field.
            FormSection(
                header = stringResource(R.string.headline),
                // Material, so the language being learned — like the talk
                // titles it stands in for.
                footer = stringResource(R.string.write_it_in,
                    com.roro.futurevoice.data.LanguageCatalog.ownName(targetLanguage, nativeLanguage)),
            ) {
                data.topics.forEach { t ->
                    Row(
                        Modifier.fillMaxWidth().clickable {
                            ownText = ""
                            headline = t
                        }.padding(horizontal = 16.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(t, style = MaterialTheme.typography.bodyLarge, maxLines = 2,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f))
                        if (t == headline) {
                            androidx.compose.material3.Icon(androidx.compose.material.icons.Icons.Filled.Check,
                                contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(start = 8.dp).size(20.dp))
                        }
                    }
                    FormDivider()
                }
                FormTextRow(
                    value = ownText,
                    onChange = { text ->
                        ownText = text
                        // Typing takes the headline; clearing the field hands
                        // it back to the automatic pick.
                        headline = text.trim().ifEmpty { data.topics.firstOrNull().orEmpty() }
                    },
                    placeholder = stringResource(R.string.or_write_your_own),
                )
            }

            // Said plainly because it is the whole privacy story of this
            // feature: the photo is the place, and nothing else about where
            // the learner was is kept.
            FormSection(
                header = stringResource(R.string.photo),
                footer = stringResource(R.string.where_you_studied_that_day_the_photo_is_the_place_nothing_el_642592),
            ) {
                FormActionRow(androidx.compose.material.icons.Icons.Outlined.PhotoCamera,
                    stringResource(R.string.take_a_photo)) {
                    cameraPermission.launch(android.Manifest.permission.CAMERA)
                }
                FormDivider(inset = 52.dp)
                FormActionRow(androidx.compose.material.icons.Icons.Outlined.PhotoLibrary,
                    stringResource(R.string.choose_a_photo)) { imagePicker.launch("image/*") }
                if (photo != null) {
                    FormDivider(inset = 52.dp)
                    FormActionRow(androidx.compose.material.icons.Icons.Outlined.Delete,
                        stringResource(R.string.remove_photo), destructive = true) {
                        photo = null
                        DayCardStore.removePhoto(context, data.date)
                    }
                }
            }
        }
    }
}

/** A Form button row as iOS draws `Label(_, systemImage:)` in a Form: icon
 *  and title both in the tint (red when destructive, grey when disabled). */
@Composable
private fun FormActionRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    enabled: Boolean = true,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    val tint = when {
        !enabled -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
        destructive -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.primary
    }
    Row(
        Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        androidx.compose.material3.Icon(icon, contentDescription = null, tint = tint,
            modifier = Modifier.size(22.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge, color = tint)
    }
}

private enum class SaveState { IDLE, SAVING, SAVED }

/**
 * The PNG into the shared gallery (Pictures/nawana) — the same bytes the
 * share sheet hands out. API 29+ goes through MediaStore with no permission
 * and holds the row PENDING until the bytes are written, so the gallery
 * never shows a half-written picture.
 */
private suspend fun saveToGallery(context: android.content.Context, bmp: Bitmap): Boolean =
    withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,
                "nawana-day-${System.currentTimeMillis()}.png")
            put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                put(android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                    android.os.Environment.DIRECTORY_PICTURES + "/nawana")
                put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return@withContext false
        val written = runCatching {
            resolver.openOutputStream(uri)?.use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) } ?: false
        }.getOrDefault(false)
        if (!written) {
            resolver.delete(uri, null, null)
            return@withContext false
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            resolver.update(uri, android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
            }, null, null)
        }
        true
    }
