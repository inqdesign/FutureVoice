package com.roro.futurevoice.ui

import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CounterpartPhotoStore
import kotlinx.coroutines.launch

/**
 * A person's photo for the given id, as an image — null when none is on file.
 * Follows [CounterpartPhotoStore.revision], so a bubble refreshes the moment
 * the photo changes.
 */
@Composable
fun rememberPersonPhoto(id: String?): ImageBitmap? {
    val context = LocalContext.current
    val revision by CounterpartPhotoStore.revision.collectAsStateWithLifecycle()
    return remember(id, revision) {
        id?.let { CounterpartPhotoStore.load(context, it)?.asImageBitmap() }
    }
}

/**
 * THE counterpart avatar (iOS `PersonBubble`): the person's photo when one is
 * on file, else their initials on the accent. Every surface that shows a
 * person — the stories row, the composer, the scene's speaker label, the book
 * cover — draws through this one view so they can't drift apart.
 */
@Composable
fun PersonBubble(name: String, photoId: String?, size: Dp = 64.dp, photo: ImageBitmap? = null) {
    val shown = photo ?: rememberPersonPhoto(photoId)
    val accent = MaterialTheme.colorScheme.primary
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(accent.copy(alpha = 0.15f), CircleShape)
            .border(1.5.dp, accent.copy(alpha = 0.35f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (shown != null) {
            Image(shown, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.size(size).clip(CircleShape))
        } else {
            Text(initials(name).ifEmpty { "?" },
                fontSize = (size.value * 0.34f).sp,
                fontWeight = FontWeight.SemiBold,
                color = accent)
        }
    }
}

/**
 * The one control for picking a person's photo (iOS `PersonPhotoButton`) — a
 * menu over whatever the host draws. Three sources: the photo picker, the
 * camera, and Files; a file is read where it lives and never copied. The image
 * comes back decoded and squared — the host decides whether it is saved now or
 * held until the person exists.
 */
@Composable
fun PersonPhotoButton(
    onImage: (Bitmap) -> Unit,
    onRemove: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    fun fromUri(uri: android.net.Uri?) {
        uri ?: return
        scope.launch {
            val bmp = CounterpartPhotoStore.decode(context, uri)
            if (bmp != null) onImage(bmp) else error = true
        }
    }
    val library = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { fromUri(it) }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { fromUri(it) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bmp ->
        if (bmp != null) onImage(CounterpartPhotoStore.square(bmp))
    }
    Box {
        Box(Modifier.clip(CircleShape).clickable { open = true }) { content() }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.photo_library)) },
                leadingIcon = { Icon(Icons.Filled.PhotoLibrary, contentDescription = null) },
                onClick = {
                    open = false
                    library.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                })
            DropdownMenuItem(
                text = { Text(stringResource(R.string.take_a_photo)) },
                leadingIcon = { Icon(Icons.Filled.CameraAlt, contentDescription = null) },
                onClick = { open = false; runCatching { camera.launch(null) } })
            DropdownMenuItem(
                text = { Text(stringResource(R.string.pick_a_file)) },
                leadingIcon = { Icon(Icons.Filled.Folder, contentDescription = null) },
                onClick = { open = false; files.launch(arrayOf("image/*")) })
            if (onRemove != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.remove_photo), color = MaterialTheme.colorScheme.error) },
                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null,
                        tint = MaterialTheme.colorScheme.error) },
                    onClick = { open = false; onRemove() })
            }
        }
    }
    if (error) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { error = false },
            confirmButton = { androidx.compose.material3.TextButton(onClick = { error = false }) {
                Text(stringResource(R.string.ok)) } },
            text = { Text(stringResource(R.string.couldn_t_read_that_photo)) },
        )
    }
}
