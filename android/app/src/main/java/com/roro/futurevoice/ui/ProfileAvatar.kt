package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.roro.futurevoice.data.AvatarStore

/**
 * A circular profile avatar: the learner's photo when set, otherwise their
 * initials, otherwise a neutral person glyph. One composable so the home
 * header and the profile editor always agree.
 */
@Composable
fun ProfileAvatar(initials: String = "", size: androidx.compose.ui.unit.Dp = 32.dp) {
    val context = LocalContext.current
    val revision by AvatarStore.revision.collectAsStateWithLifecycle()
    val bitmap = remember(revision) { AvatarStore.load(context) }
    val letters = remember(initials) {
        initials.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
            .take(2).joinToString("") { it.take(1).uppercase() }
    }
    Box(Modifier.size(size).clip(CircleShape)
        .background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
        when {
            bitmap != null -> androidx.compose.foundation.Image(
                bitmap.asImageBitmap(), contentDescription = null,
                contentScale = ContentScale.Crop, modifier = Modifier.size(size))
            letters.isNotEmpty() -> Text(letters, fontSize = (size.value * 0.42f).sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            else -> Icon(Icons.Filled.Person, contentDescription = null,
                modifier = Modifier.size(size * 0.6f),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
