package com.roro.futurevoice.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Rect
import android.media.ExifInterface
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * A person's profile photo — one small square JPEG per [Counterpart], keyed by
 * id, under `files/counterpart_photos/` (iOS `CounterpartPhotoStore`,
 * `59c6481`). Same rules as the learner's own avatar: re-encoded through a
 * fresh bitmap on save, so EXIF and location never survive, and never more
 * pixels than a circle on screen needs. Local only — a photo of someone the
 * learner knows is theirs to keep on this phone.
 *
 * [revision] bumps on every write so every bubble refreshes the moment a
 * photo changes, without the store holding decoded images for people who are
 * not on screen.
 */
object CounterpartPhotoStore {
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> = _revision
    private val cache = HashMap<String, Bitmap>()

    private fun dir(context: Context) = File(context.filesDir, "counterpart_photos").also { it.mkdirs() }
    private fun file(context: Context, id: String) = File(dir(context), "$id.jpg")

    fun has(context: Context, id: String): Boolean =
        synchronized(cache) { cache.containsKey(id) } || file(context, id).length() > 0

    fun load(context: Context, id: String): Bitmap? {
        synchronized(cache) { cache[id]?.let { return it } }
        val f = file(context, id)
        if (f.length() <= 0) return null
        val bmp = runCatching { BitmapFactory.decodeFile(f.absolutePath) }.getOrNull() ?: return null
        synchronized(cache) { cache[id] = bmp }
        return bmp
    }

    /** Decode a picked image (photo picker or Files), upright it, square it. */
    suspend fun decode(context: Context, uri: Uri): Bitmap? = withContext(Dispatchers.IO) {
        val bytes = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }.getOrNull() ?: return@withContext null
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@withContext null
        val degrees = runCatching {
            when (ExifInterface(bytes.inputStream()).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        }.getOrDefault(0f)
        val upright = if (degrees == 0f) source else Bitmap.createBitmap(
            source, 0, 0, source.width, source.height, Matrix().apply { postRotate(degrees) }, true)
        square(upright)
    }

    /** Aspect-fill into a square of side min(512, shorter edge). */
    fun square(source: Bitmap): Bitmap {
        val side = minOf(source.width, source.height).coerceAtLeast(1)
        val target = minOf(512, side)
        val out = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(
            source,
            Rect((source.width - side) / 2, (source.height - side) / 2,
                (source.width + side) / 2, (source.height + side) / 2),
            Rect(0, 0, target, target), null)
        return out
    }

    suspend fun save(context: Context, id: String, picked: Bitmap) = withContext(Dispatchers.IO) {
        val sq = if (picked.width == picked.height && picked.width <= 512) picked else square(picked)
        runCatching {
            val f = file(context, id)
            val tmp = File(f.parentFile, f.name + ".tmp")
            tmp.outputStream().use { sq.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        }
        synchronized(cache) { cache[id] = sq }
        _revision.value += 1
    }

    fun delete(context: Context, id: String) {
        file(context, id).delete()
        synchronized(cache) { cache.remove(id) }
        _revision.value += 1
    }
}
