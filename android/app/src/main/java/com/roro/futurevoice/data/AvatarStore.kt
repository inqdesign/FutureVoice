package com.roro.futurevoice.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Rect
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The learner's own profile photo. Neither Google nor Apple sign-in returns
 * one reliably, so the picture is something they pick themselves. Stored as
 * one square JPEG in files/; [revision] bumps on every write so every avatar
 * on screen refreshes the moment it changes.
 */
object AvatarStore {
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> = _revision

    fun file(context: Context) = File(context.filesDir, "profile_avatar.jpg")
    fun exists(context: Context) = file(context).length() > 0

    fun load(context: Context): Bitmap? =
        runCatching { BitmapFactory.decodeFile(file(context).absolutePath) }.getOrNull()

    /** Center-crop to a square and downscale before saving — an avatar never
     *  needs more than a small circle's worth of pixels. */
    suspend fun save(context: Context, uri: Uri): Boolean = withContext(Dispatchers.IO) {
        val source = runCatching {
            context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it) }
        }.getOrNull() ?: return@withContext false
        val side = minOf(source.width, source.height)
        val target = minOf(512, side)
        val square = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
        Canvas(square).drawBitmap(
            source,
            Rect((source.width - side) / 2, (source.height - side) / 2,
                (source.width + side) / 2, (source.height + side) / 2),
            Rect(0, 0, target, target), null)
        runCatching {
            file(context).outputStream().use { square.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        }.onFailure { return@withContext false }
        _revision.value += 1
        true
    }

    fun clear(context: Context) {
        file(context).delete()
        _revision.value += 1
    }
}
